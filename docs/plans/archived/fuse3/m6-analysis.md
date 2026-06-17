# M6 Analysis: Multithreaded Loop Support

Status: analysis complete; M7 implementation is complete.

Depends on M5, which is complete.

## Goal

Analyze whether and how `ocamlfuse3` should support libfuse's multithreaded
high-level event loop while keeping the Ubuntu Jammy/libfuse `3.10` support
constraint and OCaml runtime rules intact.

## Runtime State After M7

`lib/Fuse_util.c` now:

- parses FUSE command-line options with `fuse_parse_cmdline`;
- creates a high-level FUSE handle with `fuse_new`;
- mounts with `fuse_mount`;
- forces foreground operation with `fuse_daemonize(1)`;
- installs signal handlers;
- releases the OCaml runtime while blocked in `fuse_loop` or `fuse_loop_mt`;
- reacquires the OCaml runtime after the FUSE loop returns;
- acquires and releases the OCaml runtime in every FUSE callback wrapper before
  calling OCaml.

The default binding behavior remains single-threaded from libfuse's point of
view. FUSE waits for one callback to return before invoking another callback.
User code can opt into libfuse worker-thread dispatch with
`~loop_mode:Multi_threaded`.

The FUSE 3 runtime does not dispatch requests through an OCaml thread pool. The
old `lib/Thread_pool.ml` module was removed in M8.

## Local API Findings

The local development environment has libfuse `3.14.0`, but the binding targets
`FUSE_USE_VERSION 30` and must support libfuse `3.10`.

With `FUSE_USE_VERSION < 32`, the installed headers expose:

```c
int fuse_loop_mt_31(struct fuse *f, int clone_fd);
#define fuse_loop_mt(f, clone_fd) fuse_loop_mt_31(f, clone_fd)
```

With newer API levels, the signature changes to a configuration object:

```c
int fuse_loop_mt_32(struct fuse *f, struct fuse_loop_config *config);
int fuse_loop_mt(struct fuse *f, struct fuse_loop_config *config);
```

The newer configuration path can expose controls such as maximum worker
threads, but `FUSE_USE_VERSION 30` cannot pass a `struct fuse_loop_config` to
`fuse_loop_mt`. For the first Jammy-compatible multithreaded implementation,
the practical high-level API is therefore:

```c
fuse_loop_mt(fuse, opts.clone_fd)
```

`struct fuse_cmdline_opts` contains:

- `singlethread`;
- `clone_fd`;
- `max_idle_threads`;
- `max_threads`, added in libfuse `3.12`.

Because `max_threads` was added after the Jammy target and the API 30
`fuse_loop_mt` signature cannot receive the config object, M6 should not design
the first multithreaded implementation around max-thread controls.

## OCaml Runtime Findings

The OCaml 5 headers state that a C-created thread must call
`caml_c_thread_register` before calling into OCaml or using runtime functions,
and must call `caml_c_thread_unregister` before the thread finishes. The
registration call returns without holding the domain lock.

The existing callback wrappers are correct for callbacks invoked on an
OCaml-known thread:

```c
caml_acquire_runtime_system();
/* call OCaml */
caml_release_runtime_system();
```

They are not sufficient for libfuse worker threads created by `fuse_loop_mt`,
because those threads are created by C code outside the OCaml runtime. Calling
`caml_acquire_runtime_system` from an unregistered libfuse worker thread is not
a safe runtime model.

## Recommended Decision

Support a multithreaded loop only as an explicit opt-in mode. Keep the default
loop single-threaded.

Reasons:

- It preserves existing behavior for filesystem implementations that assume one
  callback at a time.
- It avoids silently exposing user callbacks to reentrancy and logical races.
- It keeps the current examples, smoke tests, and default runtime conservative.
- It still allows users with thread-safe callback code to opt in.

## Recommended API Shape

Add a small public loop-mode configuration without changing callback records:

```ocaml
type loop_mode = Single_threaded | Multi_threaded

val main : ?loop_mode:loop_mode -> Fuse_bindings.str array -> operations -> unit
```

Default behavior should be `Single_threaded`. `Fuse.Fuse_compat.main` should
accept the same optional loop-mode argument so users can test threading without
porting all callbacks to the native operation record first.

If `loop_mode = Multi_threaded` and the parsed FUSE options contain
`singlethread`, the implementation should prefer single-threaded execution.
The command-line `-s` option is a standard user request and should remain a
force-single-thread escape hatch.

For the first implementation, do not expose max-thread controls. The API 30
high-level loop cannot pass them to libfuse in a Jammy-compatible way.

## Recommended C Runtime Model

Implement multithreaded callbacks with per-thread OCaml runtime registration:

1. Create a `pthread_key_t` with `pthread_once`.
2. Before entering the FUSE loop on the OCaml caller thread, mark that thread as
   OCaml-owned in the thread-local key.
3. When a callback is invoked on a thread without that marker, call
   `caml_c_thread_register`.
4. Store a thread-local marker showing that the binding registered this thread.
5. Call `caml_acquire_runtime_system`, execute the existing callback body, then
   call `caml_release_runtime_system`.
6. Use the pthread key destructor to call `caml_c_thread_unregister` for
   threads registered by the binding.

The destructor must not unregister the OCaml caller thread. Use distinct marker
values for:

- an OCaml-owned thread that should not be unregistered by the binding;
- a libfuse worker thread registered by the binding.

If worker-thread registration fails, the callback should return an intentional
failure. For integer-returning FUSE callbacks, use `-EIO`. For `init`, record a
fatal status and return `NULL`.

## Concurrency Semantics To Document

Even with `fuse_loop_mt`, OCaml bytecode or native OCaml code still runs under
the OCaml runtime's domain lock. Pure OCaml callback execution is therefore
serialized at runtime entry.

Multithreaded FUSE can still change behavior:

- another callback can run while a callback is inside C code that released the
  OCaml runtime;
- helper stubs such as blocking Unix operations can allow interleaving;
- callback order becomes nondeterministic;
- filesystem implementations must protect shared logical state when operations
  may interleave.

Documentation should say that opt-in multithreaded mode is for filesystems
whose callbacks are written to tolerate reentrant FUSE requests and
interleaving around blocking operations.

## `Thread_pool` Recommendation

Do not use `lib/Thread_pool.ml` for the FUSE 3 multithreaded loop. libfuse owns
worker-thread creation and request dispatch in `fuse_loop_mt`; the old OCaml
thread pool does not solve foreign-thread registration and is not part of the
current runtime path.

M8 removed the old thread-pool module as unrelated dead code. Multithreaded
support uses libfuse-created workers plus OCaml foreign-thread registration.

## Testing Recommendations

Add multithreaded coverage separately from the default smoke test:

- keep `make e2e-smoke-test` focused on the default single-threaded smoke path;
- add a full-suite option or separate target that runs the e2e filesystem with
  opt-in multithreaded mode;
- include a concurrency-oriented test that makes one callback block while
  another request still completes;
- keep skip behavior unchanged when `/dev/fuse` is unavailable;
- run the multithreaded mounted test outside the sandbox.

The concurrency test should avoid depending on callback ordering except where
the test filesystem explicitly coordinates the order with temporary files,
pipes, or another deterministic barrier.

## Implementation Milestone Proposal

M7 implemented the follow-up work after this analysis:

1. Add `loop_mode` to `Fuse.ml` and `Fuse.mli`.
2. Extend `Fuse.Fuse_compat.main` with the same optional loop-mode control.
3. Extend `ml_fuse_main` to receive the selected loop mode.
4. In C, route to `fuse_loop` for single-threaded mode.
5. In C, route to `fuse_loop_mt(fuse, opts.clone_fd)` for multithreaded mode
   unless `opts.singlethread` is set.
6. Add pthread TLS registration and unregister cleanup for libfuse worker
   threads.
7. Add tests for opt-in multithreaded execution.
8. Update README, release notes, binding docs, and agent docs.

## Verification For The Analysis

The analysis used:

```sh
pkg-config --modversion fuse3
pkg-config --cflags --libs fuse3
rg -n "fuse_loop_mt|struct fuse_loop_config|clone_fd" /usr/include/fuse3
rg -n "caml_c_thread_register|caml_c_thread_unregister" $(ocamlc -where)/caml
rg -n "fuse_loop_mt|caml_c_thread_register|Thread_pool|single-thread|multithread" lib docs
```

Local results:

- libfuse version: `3.14.0`;
- compile/link flags: `-I/usr/include/fuse3 -lfuse3 -lpthread`;
- OCaml version: `5.4.0`;
- API 30 `fuse_loop_mt` shape: `fuse_loop_mt(f, clone_fd)`;
- OCaml C-created threads must register and unregister with the runtime.
