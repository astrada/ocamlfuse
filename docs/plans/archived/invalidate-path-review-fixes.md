# Invalidate Path Review Fixes (PR [#36](https://github.com/astrada/ocamlfuse/pull/36))

## Context

The `toots-upstream-invalidate-path` branch exposes
`Fuse.invalidate_path`, backed by libfuse's `fuse_invalidate_path`. The public
API, C stub, and lifecycle integration need follow-up work before the change is
merged:

- the published FUSE handle can still be used while teardown is unmounting the
  session;
- the C stub imposes a `PATH_MAX` limit and does not reject embedded NUL bytes;
- the public documentation describes dentry invalidation, while libfuse
  invalidates cached inode attributes and file data;
- the new behavior and teardown boundary are not covered by tests.

## Goals

- Ensure that invalidation never overlaps unmount or destruction of the
  published FUSE handle.
- Pass every valid OCaml path to libfuse without imposing an artificial
  `PATH_MAX` limit.
- Reject strings that cannot represent a single C path.
- Describe the underlying libfuse behavior accurately.
- Cover the public API, path marshalling, mounted invalidation, and shutdown
  behavior with regression tests.

## Non-goals

- Expose libfuse's low-level dentry invalidation API.
- Add support for multiple concurrent `Fuse.main` mounts in one process.
- Change the existing convention that libfuse errors are exposed as
  `Unix.EUNKNOWNERR` values.
- Edit camlidl-generated binding artifacts.

## Implementation Plan

### 1. Tighten handle publication and teardown

Update `lib/Fuse_util.c` so the global handle represents a filesystem that is
ready to enter, or is currently inside, its request loop.

1. Remove the publication immediately after `fuse_new`.
2. Publish the handle after mounting, daemonization, signal-handler setup, and
   OCaml thread registration succeed, immediately before releasing the OCaml
   runtime and entering `fuse_loop` or `fuse_loop_mt`.
3. After the loop returns and the OCaml runtime has been reacquired, clear the
   handle under `ml_fuse_handle_lock` before removing signal handlers or
   calling `fuse_unmount`.
4. Keep `ml_fuse_handle_lock` held for the complete call to
   `fuse_invalidate_path`. Clearing the handle will therefore wait for an
   in-flight invalidation, while subsequent calls will return `-ENODEV`.
5. Check every error path. Paths that fail before the loop must never publish
   the handle, and no cleanup path may unmount or destroy a published handle.
6. Rewrite the adjacent lifecycle comment to state the invariant precisely.

The intended ordering is:

```text
fuse_mount and lifecycle setup
  -> publish handle
  -> run FUSE loop
  -> unpublish handle
  -> remove signal handlers
  -> unmount
  -> destroy
```

### 2. Marshal paths without `PATH_MAX`

Replace the fixed stack buffer in `ml_fuse_invalidate_path` with a dynamically
allocated copy.

1. Read the OCaml string length while holding the OCaml runtime.
2. Reject an embedded NUL byte with `-EINVAL`; otherwise the C API would act on
   only a prefix of the requested path.
3. Allocate `len + 1` bytes, returning `-ENOMEM` if allocation fails.
4. Copy the complete string and add its terminating NUL before releasing the
   OCaml runtime.
5. Release the runtime, acquire `ml_fuse_handle_lock`, and either return
   `-ENODEV` or call `fuse_invalidate_path`.
6. Unlock, reacquire the runtime, and free the temporary allocation on every
   return path.
7. Preserve the conversion of libfuse's `-ENOENT` result to success.

### 3. Correct the public description

Update `lib/Fuse.mli` and `docs/release-notes.md` to match libfuse's actual
contract:

- `fuse_invalidate_path` looks up the path in libfuse's internal cache and
  calls `fuse_lowlevel_notify_inval_inode`;
- it invalidates cached inode attributes and file contents, not the cached
  name or dentry;
- a path unknown to libfuse is treated as an already-satisfied invalidation;
- with writeback caching, the call may block while dirty pages are written
  back;
- callers must not invoke it from an execution path, or while holding a lock,
  that is needed to service the resulting filesystem work;
- calls made without a live published mount raise `Unix.Unix_error` carrying
  `ENODEV` through the existing `Unix.EUNKNOWNERR` representation.

Do not claim that the next name lookup necessarily reaches the filesystem. A
future dentry-invalidation API would require a separate low-level binding and
is outside this work.

### 4. Add regression coverage

#### Compile and marshalling checks

Add unit coverage under `test/unit/` for the following behavior:

- `Fuse.invalidate_path` has type `string -> unit`.
- Without a live mount, a short path and a path longer than `PATH_MAX` reach
  the same `ENODEV` result. This proves that the stub no longer rejects the
  long path before checking the mount state.
- A string containing an embedded NUL byte is rejected with `EINVAL` rather
  than being truncated.

The tests should assert through the public OCaml API. They may compare the
`Unix.EUNKNOWNERR` payloads where the current error-conversion convention makes
that necessary.

#### Mounted invalidation check

Extend `test/e2e/` with a control channel that asks the mounted test filesystem
process to call `Fuse.invalidate_path`; calling it from `client.exe` would use
the wrong process and therefore cannot access the published handle.

The functional test should:

1. Create and open a file through the FUSE mount.
2. Read it through the same open descriptor to populate the FUSE kernel page
   cache.
3. Change the backing file directly without routing the write through FUSE.
4. Ask `testfs.exe` to invalidate the FUSE path and wait for an acknowledgement.
5. Seek and read through the mounted descriptor again.
6. Assert that the new backing contents are visible.

Keep the contents the same length so a size change cannot make the cache update
for an unrelated reason.

#### Teardown check

Use the same control mechanism to start a background invalidation worker before
unmounting. The e2e runner should unmount normally, wait for `testfs.exe`, and
verify that:

- the worker observes `ENODEV` after the handle is unpublished;
- no unexpected libfuse error is reported during teardown;
- the filesystem process exits cleanly without needing the runner's kill
  fallback.

Make the worker bounded and synchronize its start so the test does not depend
on an arbitrary sleep. If this cannot reliably force an invalidation to be in
flight, retain it as a stress check and cover the publication ordering with a
smaller test hook rather than accepting a timing-dependent assertion.

## Formatting and Validation

After implementing the changes:

1. Format the touched sources:

   ```sh
   tools/format_c lib/Fuse_util.c
   tools/format_ocaml lib/Fuse.ml lib/Fuse.mli test/unit/<changed-files> \
     test/e2e/testfs.ml test/e2e/client.ml
   ```

2. Run the required build and unit tests sequentially:

   ```sh
   dune build @install
   make test
   ```

3. Build the public examples:

   ```sh
   dune build example/hello.exe example/fusexmp.exe
   ```

4. Run mounted tests outside the sandbox:

   ```sh
   make e2e-smoke-test
   make e2e-single-threaded-smoke-test
   make e2e-multithreaded-smoke-test
   make e2e
   ```

Run additional explicit single-threaded or multithreaded full suites if the
teardown test is mode-specific or reveals different behavior between loops.

## Acceptance Criteria

- The handle is not published before the filesystem is ready to enter its
  loop.
- The handle is unpublished before unmount begins.
- Teardown waits for every invalidation that already acquired the handle lock.
- Paths longer than `PATH_MAX` are passed to libfuse.
- Embedded NUL bytes are rejected without invalidating a prefix path.
- Documentation describes inode attribute/data invalidation and does not
  promise dentry invalidation.
- Unit, compile, example, and mounted regression tests pass.
- The e2e runner observes a clean filesystem-process exit during the teardown
  check.
