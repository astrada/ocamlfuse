# Supplemental Analysis: OCaml And libfuse3 Worker Threads

This note records external analysis about using libfuse3's multithreaded loop
from OCaml 5. It is supplemental context for `m6-analysis.md` and `m7-plan.md`;
the repo-native implementation plan remains `m7-plan.md`.

## Question

The binding should support libfuse3's multithreaded loop. Since libfuse creates
worker threads directly in C, do those threads need to be registered with the
OCaml runtime before they call OCaml callbacks?

## Answer

Yes. Libfuse-created POSIX threads are foreign to the OCaml runtime. Before one
of those threads touches OCaml values or calls OCaml callbacks, it must be
registered with the OCaml runtime and must hold the runtime lock.

For OCaml 5, the relevant functions are declared in `<caml/threads.h>`:

```c
int caml_c_thread_register(void);
void caml_c_thread_unregister(void);
```

`caml_c_thread_register` attaches the current C thread to the OCaml runtime and
returns without holding the domain lock. The callback wrapper must then acquire
the runtime before calling OCaml and release it before returning to libfuse.

## Callback-Side Registration

Libfuse owns worker-thread creation, so the binding generally cannot intercept
the `pthread_create` calls directly. Instead, each callback wrapper should
ensure that the current thread is ready for OCaml before invoking the registered
OCaml callback.

The usual pattern is:

```c
static _Thread_local int ocaml_thread_registered = 0;

static int ensure_ocaml_thread_ready(void) {
  if (!ocaml_thread_registered) {
    if (caml_c_thread_register() != 0)
      return -1;
    ocaml_thread_registered = 1;
  }

  caml_acquire_runtime_system();
  return 0;
}

static void release_ocaml_thread(void) {
  caml_release_runtime_system();
}
```

The repository plan uses pthread TLS rather than `_Thread_local` so it can add a
destructor that calls `caml_c_thread_unregister` when a libfuse worker exits.
It also distinguishes OCaml-owned threads from binding-registered libfuse
workers, so the binding does not unregister the OCaml caller thread.

## Important Limitations

`caml_c_thread_register` registers foreign worker threads with the OCaml
runtime, but it does not make OCaml callback execution parallel. Callbacks still
run under the OCaml runtime lock for the registered domain. Multithreaded FUSE
can still change behavior because callbacks may interleave around blocking C or
Unix calls that release the runtime.

The binding should continue forcing foreground-oriented FUSE operation. The
current lifecycle calls `fuse_daemonize(1)` after mount setup, which avoids the
standard high-level `fuse_main` daemonization path. Daemonization and `fork`
remain risky with OCaml 5 runtime state and should not be reintroduced casually.

## References

- <https://discuss.ocaml.org/t/os-threads-of-external-origin/15331>
- <https://discuss.ocaml.org/t/caml-c-thread-register-in-programs-that-do-not-use-systhreads/9232>
- <https://discuss.ocaml.org/t/ocaml-5-0-and-c-interface/10856>
- <https://ocaml.org/manual/5.1/libthreads.html>
- <https://discuss.ocaml.org/t/multicore-and-fork-called-from-c-bindings/13993>
