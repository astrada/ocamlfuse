# ThreadSanitizer Testing

## Purpose

Use this note when testing `fuse3` with an OCaml switch built with
ThreadSanitizer, such as an `ocaml-option-tsan` switch.

## Compiler Startup

If even simple compiler commands fail with:

```text
FATAL: ThreadSanitizer: unexpected memory mapping
```

reduce Linux address-space randomization for the current boot:

```sh
sudo sysctl vm.mmap_rnd_bits=30
```

After that, `ocamlopt -config` should run normally and report:

```text
tsan: true
```

The native compiler flags should also include `-fsanitize=thread`.

## Runtime Suppression

The repository contains `tsan_suppression.txt` with:

```text
mutex:caml_plat_lock_blocking
```

This suppresses a known OCaml runtime/systhreads mutex report seen in the e2e
client process under TSAN:

```text
WARNING: ThreadSanitizer: double lock of a mutex
caml_plat_lock_blocking
caml_acquire_domain_lock
st_masterlock_acquire
caml_thread_start
```

The report is in the OCaml runtime/systhreads startup path for the OUnit e2e
client, not in `testfs.exe`, `Fuse_util.c`, or the libfuse callback path.

## Build And Unit Checks

From a TSAN-enabled switch:

```sh
dune clean
dune build @install
dune runtest
dune build example/hello.exe example/fusexmp.exe
```

These checks do not require `/dev/fuse`.

## Mounted Multithreaded E2E

Mounted e2e tests require Linux, `/dev/fuse`, and mount permissions, so run
them outside the sandbox. To fail on unsuppressed sanitizer reports while
suppressing the OCaml runtime mutex warning, use:

```sh
OCAMLFUSE_E2E_REQUIRE_FUSE=1 \
TSAN_OPTIONS="halt_on_error=1:second_deadlock_stack=1:suppressions=$PWD/tsan_suppression.txt" \
make e2e-multithreaded
```

Expected successful output:

```text
Ran: 10 tests
OK
```

Without the suppression file, the multithreaded suite can fail before testing
the binding because TSAN stops on the OCaml runtime mutex warning in
`client.exe`.

## Interpreting Results

A passing suppressed multithreaded e2e run is useful signal for the binding's
libfuse-created worker-thread path:

- `fuse_loop_mt` is used by explicit multithreaded mode.
- libfuse-created worker threads enter OCaml callbacks.
- the callback path registers foreign threads with the OCaml runtime.
- the mounted filesystem handles the deterministic blocked-callback
  concurrency check.

Treat fatal sanitizer failures without a normal TSAN race stack as
inconclusive. In particular, `ThreadSanitizer:DEADLYSIGNAL` with a nested
sanitizer crash may indicate TSAN/runtime incompatibility rather than a
project data race.
