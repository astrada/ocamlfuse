# End-To-End Test Suite Plan

## Goal

Add a small end-to-end test suite for `ocamlfuse` that provides:

- A fast smoke test proving that an OCaml FUSE filesystem can be built, mounted,
  read through the kernel FUSE path, and unmounted.
- A basic functionality test that exercises every FUSE method currently exposed
  by `Fuse.operations`.
- OUnit2-based assertions for client-side behavior checks.
- Predictable skip behavior when the host cannot run FUSE mounts.

The suite should be fast enough for local pre-commit use, but it must not hang
or fail unclearly on machines without `/dev/fuse`, libfuse runtime access, or
mount permissions.

## Proposed Shape

Create a `test/e2e/` directory with:

- `testfs.ml`: a deterministic test filesystem backed by a temporary directory.
- `client.ml`: an OUnit2 test executable that performs filesystem operations
  through the mounted path and asserts results.
- `xattr_stubs.c`: test-only C helpers for `setxattr`, `getxattr`, `listxattr`,
  and `removexattr`, avoiding dependency on Python or `attr` command-line
  tools.
- `run.sh`: a harness that builds the test binaries, checks whether FUSE can be
  mounted, starts the filesystem in foreground mode, runs the client, and always
  attempts cleanup.
- `dune`: test executables and any aliases used by the harness.

Add OUnit2 as a test dependency. In Dune, the client executable should link
against `ounit2`; the package metadata should declare `ounit2` with a test-only
dependency constraint.

Format new OCaml test sources with `tools/format_ocaml test/e2e/testfs.ml
test/e2e/client.ml`.

Prefer a purpose-built filesystem over `example/fusexmp.ml`. `fusexmp` passes
FUSE paths directly to Unix calls, so it mirrors `/` and is not a safe backing
filesystem for write tests.

## Test Filesystem Design

The test filesystem should map FUSE paths into a temporary backing root:

- `/` maps to `$BACKING_ROOT`.
- `/dir/file` maps to `$BACKING_ROOT/dir/file`.
- Paths should be normalized defensively and rejected if they would escape the
  backing root.

The filesystem should implement the full current `Fuse.operations` record:

- `init`
- `getattr`
- `readlink`
- `mknod`
- `mkdir`
- `unlink`
- `rmdir`
- `symlink`
- `rename`
- `link`
- `chmod`
- `chown`
- `truncate`
- `utime`
- `fopen`
- `read`
- `write`
- `statfs`
- `flush`
- `release`
- `fsync`
- `setxattr`
- `getxattr`
- `listxattr`
- `removexattr`
- `opendir`
- `readdir`
- `releasedir`
- `fsyncdir`

For file handles, use `Unix_util.int_of_file_descr` and
`Unix_util.file_descr_of_int`, matching the existing examples. For xattrs, store
values in an in-memory table keyed by path and attribute name. This keeps the
FUSE callback behavior testable even when the backing directory filesystem lacks
xattr support.

Each callback should append a compact event line to a log file. The client can
then assert that expected callbacks were actually reached, not only that the
final file state looks correct.

## Harness Behavior

`run.sh` should:

1. Build the test binaries with Dune.
2. Create a temporary backing root, mountpoint, callback log, and readiness
   marker under `${TMPDIR:-/tmp}`.
3. Check FUSE prerequisites:
   - libfuse is already required by the build.
   - `/dev/fuse` exists and is accessible on Linux.
   - an unmount command is available: `fusermount -u`, `fusermount3 -u`, or
     `umount`.
   - the current user can mount FUSE filesystems.
4. If prerequisites are missing, print `SKIP` and exit `0` by default.
5. If `OCAMLFUSE_E2E_REQUIRE_FUSE=1` is set, treat missing prerequisites as a
   failure.
6. Start the filesystem with foreground mode (`-f`) and a test-specific
   filesystem name.
7. Wait for a readiness marker from `init` and poll the mountpoint before
   running the client.
8. Run the selected test mode with a short timeout.
9. On exit, unmount, terminate the filesystem process if still running, and
   remove temporary files.

Use conservative timeouts around mount readiness, OUnit2 client execution,
unmount, and process termination. On failure, print the callback log and
relevant process state.

## Test Modes

Provide two modes:

- `smoke`: mount the test filesystem, `stat` the root, create or read one small
  file, verify contents through the mountpoint, and unmount.
- `full`: run the complete callback matrix below.

`make test` should run `smoke`. The full suite should be easy to run
explicitly, for example:

```sh
test/e2e/run.sh full
```

Add Makefile targets once the scripts exist:

```make
test:
	dune build @install
	test/e2e/run.sh smoke

e2e:
	dune build @install
	test/e2e/run.sh full
```

Avoid making mount-based tests an unconditional Dune `@runtest` requirement
unless the skip behavior is proven reliable on supported platforms.

## Functional Coverage Matrix

The full mode should perform operations through the mounted path and verify both
observable behavior and callback log entries.

| Operation | Client action | Expected result |
| --- | --- | --- |
| `init` | start filesystem | readiness marker exists and log contains `init` |
| `getattr` | `stat` root and files | metadata is returned |
| `statfs` | call `statvfs` on mountpoint | filesystem stats are returned |
| `opendir`, `readdir`, `releasedir` | list root and a directory | expected entries appear |
| `mkdir`, `rmdir` | create and remove a directory | directory lifecycle succeeds |
| `mknod`, `fopen`, `write`, `flush`, `release` | create, write, and close a file | file exists with expected contents |
| `read` | reopen and read file | contents match |
| `fsync` | fsync an open file | call succeeds and callback is logged |
| `fsyncdir` | fsync an open directory | call succeeds or is skipped with a clear platform reason |
| `truncate` | shrink and extend a file | size changes as expected |
| `chmod` | change file mode | mode bits change as expected |
| `chown` | set current uid/gid | succeeds when permitted, otherwise reports a targeted skip |
| `utime` | set atime/mtime | timestamps change within tolerance |
| `symlink`, `readlink` | create and read a symlink | target string matches |
| `link` | create a hard link | link count or equivalent content check succeeds |
| `rename` | rename a file | old path disappears and new path exists |
| `unlink` | unlink files and links | paths disappear |
| `setxattr`, `getxattr`, `listxattr`, `removexattr` | manipulate a `user.ocamlfuse_test` xattr | value round-trips, appears in list, then disappears |

## Client Implementation Notes

Use an OUnit2 client executable rather than shell assertions for most checks.
This keeps the suite portable and avoids relying on optional commands such as
`stat`, `getfattr`, or `setfattr`.

The client should:

- Define separate OUnit2 test cases for smoke behavior and each full-mode
  operation group.
- Use `Unix` and `Unix.LargeFile` operations for file behavior.
- Use test-only xattr externals backed by `xattr_stubs.c`.
- Use OUnit2 assertions so failures identify the exact operation and expected
  value.
- Use `skip_if` only for known platform or permission constraints inside full
  mode.
- Check the callback log after each group of related operations.
- Use unique names per run to avoid stale state.

## Portability

The first supported target is Linux with libfuse 2. macOS/macFUSE support is out
of scope for the first version.

Platform-sensitive operations should be handled explicitly:

- xattr C stubs should use the Linux xattr API for the first version.
- `chown` may be restricted by user permissions; use the current uid/gid and
  skip only for known permission errors.
- `fsync` on directories is not uniformly supported; skip only this assertion if
  the platform returns a known unsupported error.
- Hard links may be restricted on some filesystems; report a targeted skip
  rather than hiding unrelated failures.

## CI Strategy

Use two layers in CI:

- Always run `dune build @install` and build the test binaries.
- Run `make test` on jobs that have FUSE available. This runs the smoke test.

For CI jobs intended to validate FUSE behavior, set
`OCAMLFUSE_E2E_REQUIRE_FUSE=1` so missing mount support fails loudly. For
general package builds, leave it unset so the e2e suite skips cleanly.

## Decisions

- `make test` runs the smoke test.
- The first version targets Linux only.
- Test-only C xattr helpers are acceptable.
- The first version is single-threaded; multithreaded smoke coverage can be
  added after the basic suite is stable.
