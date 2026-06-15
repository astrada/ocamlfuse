# M7 Plan: Opt-In libfuse Multithreaded Loop

Status: planned; recommendations accepted.

Depends on M6, which selected direct `fuse_loop_mt` support with explicit
foreign-thread registration instead of an OCaml-owned custom session loop.

## Goal

Implement the first opt-in multithreaded runtime path by using libfuse's own
high-level multithreaded loop:

```c
fuse_loop_mt(fuse, opts.clone_fd)
```

The default runtime must remain single-threaded. Multithreading should be
activated only when user code passes `~loop_mode:Multi_threaded`, and FUSE `-s`
must continue to force the effective path back to single-threaded execution.

## Non-Goals

- Do not reimplement `fuse_session_loop`.
- Do not use `Thread_pool` for FUSE request processing.
- Do not expose max-thread controls in the public API.
- Do not require libfuse APIs newer than the Jammy/libfuse `3.10` target.
- Do not change callback record shapes.
- Do not make multithreading the default.

## Public API

Add a public loop-mode control:

```ocaml
type loop_mode =
  | Single_threaded
  | Multi_threaded

val main : ?loop_mode:loop_mode -> Fuse_bindings.str array -> operations -> unit
```

`Fuse.Fuse_compat.main` should accept and forward the same optional argument.

Existing calls must keep compiling:

```ocaml
Fuse.main argv ops
Fuse.Fuse_compat.main argv compat_ops
```

## C Runtime Model

Extend `ml_fuse_main` so it receives the requested loop mode from OCaml.

Recommended C behavior:

1. parse command-line options with `fuse_parse_cmdline`;
2. if `opts.singlethread` is set, force effective `Single_threaded`;
3. create and mount FUSE exactly as today;
4. install signal handlers exactly as today;
5. mark the loop caller thread as OCaml-owned in FUSE callback TLS;
6. release the OCaml runtime;
7. call `fuse_loop(fuse)` for effective `Single_threaded`;
8. call `fuse_loop_mt(fuse, opts.clone_fd)` for effective `Multi_threaded`;
9. reacquire the OCaml runtime;
10. clear the loop caller marker;
11. run the existing signal-handler, unmount, destroy, and option cleanup.

Use one loop-failure status for both `fuse_loop` and `fuse_loop_mt` unless
implementation finds a useful distinction.

## Foreign Thread Registration

Every FUSE callback wrapper must be safe when invoked from a libfuse-created
worker thread.

Add a small callback-entry layer around the existing callback wrappers:

```c
enum ml_fuse_thread_kind {
  ML_FUSE_THREAD_NONE = 0,
  ML_FUSE_THREAD_OCAML_OWNED,
  ML_FUSE_THREAD_REGISTERED_BY_BINDING
};
```

Recommended implementation:

1. initialize a `pthread_key_t` with `pthread_once`;
2. before entering the FUSE loop on the OCaml caller thread, set the key to
   `ML_FUSE_THREAD_OCAML_OWNED`;
3. on callback entry, check the key:
   - if it is `ML_FUSE_THREAD_OCAML_OWNED`, only call
     `caml_acquire_runtime_system`;
   - if it is `ML_FUSE_THREAD_REGISTERED_BY_BINDING`, only call
     `caml_acquire_runtime_system`;
   - if it is unset, call `caml_c_thread_register`, set the key to
     `ML_FUSE_THREAD_REGISTERED_BY_BINDING`, then call
     `caml_acquire_runtime_system`;
4. on callback exit, call `caml_release_runtime_system`;
5. use the pthread-key destructor to call `caml_c_thread_unregister` only for
   threads marked `ML_FUSE_THREAD_REGISTERED_BY_BINDING`.

Do not unregister the OCaml caller thread.

`caml_c_thread_register` returns an `int`. If registration fails, callbacks
should return an intentional FUSE error:

- ordinary integer-returning callbacks return `-EIO`;
- `init` records the failure and returns `NULL`;
- `ml_fuse_main` should convert the recorded fatal registration failure into a
  clear final status if the loop itself returns success.

## Callback Wrapper Changes

The current generated callback macro does this directly:

```c
caml_acquire_runtime_system();
OPNAME##_RTYPE ret = gm281_ops_##OPNAME OPNAME##_CALL_ARGS;
caml_release_runtime_system();
```

Replace that pattern with helper functions, for example:

```c
if (ml_fuse_enter_ocaml_callback() != 0)
  return -EIO;
OPNAME##_RTYPE ret = gm281_ops_##OPNAME OPNAME##_CALL_ARGS;
ml_fuse_leave_ocaml_callback();
return ret;
```

`init` needs equivalent handling even though its return type is `void *`.

The helper must handle both single-threaded and multithreaded paths. In
single-threaded mode the FUSE callback is normally on the OCaml caller thread,
so the thread must be pre-marked as OCaml-owned before `fuse_loop`.

## Testing

Keep mounted FUSE tests separate from unit tests.

Recommended test changes:

- keep `make test` on the existing default smoke path for this branch;
- add a separate mounted multithreaded smoke target, for example
  `make e2e-multithreaded-smoke-test`;
- let `test/e2e/run.sh` accept `OCAMLFUSE_E2E_LOOP_MODE=single|multi`;
- pass `-s` only for the single-threaded e2e path;
- omit `-s` for the multithreaded e2e path;
- update `test/e2e/testfs.ml` to select `Fuse.main ~loop_mode` from the
  environment;
- keep the full e2e suite on the default single-threaded path unless the
  multithreaded smoke path proves stable enough to broaden.

Add at least one compile-oriented check that the optional `loop_mode` argument
works for both `Fuse.main` and `Fuse.Fuse_compat.main`.

## Documentation

Update active docs to say:

- default runtime remains single-threaded;
- `Multi_threaded` is opt-in;
- libfuse owns worker threads in multithreaded mode;
- the binding registers libfuse-created worker threads with the OCaml runtime
  before running callbacks;
- OCaml callback execution is still serialized by the OCaml runtime lock, but
  callback interleaving can happen around blocking C/Unix calls;
- filesystem implementations that opt in must protect shared logical state.

Also index `ocaml-libfuse3-bindings.md` as a supplemental external-analysis
note, not as a primary implementation plan.

## Exit Criteria

- Existing `Fuse.main argv ops` and `Fuse.Fuse_compat.main argv ops` compile
  unchanged.
- `Fuse.main ~loop_mode:Single_threaded` behaves like the current default.
- `Fuse.main ~loop_mode:Multi_threaded` routes through `fuse_loop_mt`.
- FUSE `-s` forces the single-threaded path even when OCaml requests
  `Multi_threaded`.
- Libfuse-created worker threads register with OCaml before acquiring the
  runtime and unregister when the worker thread exits.
- Mounted single-threaded smoke still passes.
- Mounted multithreaded smoke passes on a FUSE-capable Linux host.

## Verification

Run:

```sh
tools/format_ocaml lib/Fuse.ml lib/Fuse.mli test/e2e/testfs.ml test/unit/*.ml
tools/format_c lib/Fuse_util.c
dune build conf-libfuse3.opam ocamlfuse3.opam
dune build @install
dune build example/hello.exe example/fusexmp.exe
make test
make e2e-multithreaded-smoke-test
```

Run mounted checks outside the sandbox:

```sh
make test
make e2e-multithreaded-smoke-test
make e2e
```

Also run:

```sh
rg -n "fuse_loop_mt|caml_c_thread_register|caml_c_thread_unregister|loop_mode|OCAMLFUSE_E2E_LOOP_MODE" lib test docs Makefile
rg -n "[ \t]+$" lib test docs/plans/fuse3 Makefile
git diff --check
```
