# M10 Plan: Multithreaded e2e Test Suite

Status: planned; recommendations accepted.

Depends on M9, which renamed the public package and Dune library to `fuse3`.

## Goal

Broaden mounted end-to-end coverage for `Fuse.Multi_threaded` beyond the
current smoke test. M10 should prove both:

- the existing callback matrix works when the filesystem is mounted through
  libfuse's `fuse_loop_mt`; and
- a deterministic blocked callback does not prevent another independent FUSE
  request from completing in multithreaded mode.

This milestone is test coverage only. It should not change the public OCaml API,
the default loop mode, or callback semantics.

## Current State

The e2e runner already supports:

- `OCAMLFUSE_E2E_LOOP_MODE=single|multi`;
- `test/e2e/run.sh smoke`;
- `test/e2e/run.sh full`;
- `make e2e-smoke-test`;
- `make e2e-multithreaded-smoke-test`;
- `make e2e`.

`test/e2e/testfs.ml` already passes `~loop_mode` to `Fuse.main`.
`test/e2e/client.ml` currently runs smoke or full OUnit2 suites, but it does not
yet contain a concurrency-specific test.

## Decisions

### Target Names

Decision: add `make e2e-multithreaded`.

Rationale: the existing `make e2e` name means the full mounted suite in the
default single-threaded mode. A parallel `e2e-multithreaded` target is short,
predictable, and distinct from the existing fast
`e2e-multithreaded-smoke-test`.

### Suite Shape

Decision: run the existing full callback matrix in multithreaded mode and add
one concurrency-specific test to that multithreaded full path.

Rationale: the full callback matrix catches callback conversion regressions
under libfuse worker threads. The dedicated concurrency test catches the core
behavior that the smoke/full matrix does not prove: a request can complete while
another callback is blocked in a syscall that releases the OCaml runtime.

### Concurrency Mechanism

Decision: implement a test-only special path in `test/e2e/testfs.ml` and
coordinate it with files outside the mountpoint.

Use environment-provided control paths created by `test/e2e/run.sh`, for
example:

- `OCAMLFUSE_E2E_MT_BLOCK_MARKER`
- `OCAMLFUSE_E2E_MT_RELEASE_FIFO`

The special mounted file can be named something unlikely to collide, for
example:

```text
/__ocamlfuse_e2e_blocking_read
```

When the test filesystem receives `read` for that path, it should:

1. log `mt-block-read-enter`;
2. create the external marker file;
3. block on the external FIFO with a Unix operation that releases the OCaml
   runtime;
4. log `mt-block-read-leave`;
5. return a small static payload or EOF.

The OUnit2 client should:

1. start one OCaml thread that reads the special mounted file;
2. wait for the external marker file;
3. perform an independent mounted filesystem operation, such as creating,
   reading, and deleting a normal file;
4. assert that the independent operation completed before releasing the blocked
   read;
5. write to the external FIFO to release the blocked callback;
6. join the reader thread and fail if it raised unexpectedly.

This avoids sleep-based ordering and keeps the coordination observable outside
the FUSE mount.

### Single-Threaded Behavior

Decision: do not run the concurrency test in the default single-threaded full
suite.

Rationale: in single-threaded mode the independent request is expected to wait
behind the blocked callback. The test is meant to validate the opt-in
multithreaded path, not redefine default behavior.

## Implementation Checklist

1. Extend `test/e2e/run.sh`:
   - create a per-run control directory under `tmp_root`;
   - create a FIFO for releasing the blocked callback;
   - export the marker and FIFO paths to both test filesystem and client;
   - keep cleanup responsible for removing the control directory;
   - keep skip behavior unchanged when FUSE is unavailable.

2. Extend `test/e2e/testfs.ml`:
   - read optional multithreaded control environment variables;
   - reserve the special blocking-read path;
   - implement special `getattr`, `fopen`, `read`, and `release` behavior as
     needed for the blocking file;
   - avoid touching the backing filesystem for the special path;
   - keep normal path behavior unchanged.

3. Extend `test/e2e/client.ml`:
   - read `OCAMLFUSE_E2E_LOOP_MODE` and the multithreaded control paths;
   - add `multithreaded_concurrency_test`;
   - include it only when `mode = "full"` and `loop_mode = "multi"`;
   - keep `smoke` unchanged;
   - link the client with `threads` if it uses `Thread.create`.

4. Update `test/e2e/dune`:
   - add `threads` to the client executable libraries if required.

5. Update `Makefile`:

   ```make
   e2e-multithreaded:
   	@dune build @install
   	@OCAMLFUSE_E2E_LOOP_MODE=multi test/e2e/run.sh full
   ```

   Keep `e2e-multithreaded-smoke-test` as the fast multithreaded smoke target.

6. Update documentation:
   - `AGENTS.md`
   - `README.md`
   - `docs/release-notes.md`
   - `docs/plans/fuse3/milestones.md`
   - this plan's status/result section

## Non-Goals

- Do not make multithreaded mode the default.
- Do not add public max-thread controls.
- Do not test exact callback ordering beyond the explicit barrier points.
- Do not depend on worker thread IDs or libfuse internals.
- Do not add a custom OCaml request loop.
- Do not make mounted FUSE tests part of `make test`.

## Exit Criteria

- `make e2e-multithreaded-smoke-test` still runs only the fast smoke path in
  multithreaded mode.
- `make e2e-multithreaded` runs the full mounted suite in multithreaded mode.
- The multithreaded full suite includes one deterministic concurrency test.
- The concurrency test proves an independent mounted operation completes while
  another callback is blocked.
- `make e2e` remains the default single-threaded full mounted suite.
- Existing skip behavior for missing FUSE access remains unchanged.
- No public API or runtime behavior changes are made.

## Verification

Run sequentially:

```sh
tools/format_ocaml test/e2e/testfs.ml test/e2e/client.ml
dune build @install
make test
dune build test/e2e/testfs.exe test/e2e/client.exe test/e2e/compat_compile.exe
git diff --check
```

Run mounted checks outside the sandbox:

```sh
make e2e-smoke-test
make e2e
make e2e-multithreaded-smoke-test
make e2e-multithreaded
OCAMLFUSE_E2E_REQUIRE_FUSE=1 make e2e-multithreaded
```
