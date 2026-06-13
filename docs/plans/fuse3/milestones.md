# FUSE 3 Migration Milestones

## M0: Decisions And Environment

Status: complete. See `m0-checks.md`.

Confirm the decisions from `requirements.md` before changing code.

Exit criteria:

- Minimum libfuse 3 version is selected: `3.10`.
- `FUSE_USE_VERSION` target is selected: `30`.
- Public API strategy is selected: FUSE-3-shaped `Fuse` plus
  `Fuse.Fuse_compat`.
- FUSE 3 only versus dual FUSE 2/FUSE 3 support is decided: FUSE 3 only.
- Package naming is decided: `ocamlfuse3`.
- Conf package naming is decided: `conf-libfuse3`.
- Top-level OCaml module naming is decided: `Fuse` remains the FUSE 3 API.
- First API callback scope is decided: only callbacks needed to replace current
  behavior.
- A development environment with `pkg-config fuse3` and libfuse 3 headers is
  available. The local environment currently satisfies this with libfuse
  `3.14.0`.

Verification:

```sh
pkg-config --modversion fuse3
pkg-config --cflags --libs fuse3
```

Expected locally:

```sh
3.14.0
-I/usr/include/fuse3 -lfuse3 -lpthread
```

## M1: Build And Package Discovery

Status: complete. See `m1-plan.md`.

Update build discovery and package metadata without changing runtime behavior.

Tasks:

- Update `lib/config/discover.ml` to query `pkg-config fuse3`.
- Remove fallback flags that could silently use libfuse 2.
- Rename the Dune/opam package from `ocamlfuse` to `ocamlfuse3`.
- Rename the local conf package from `conf-libfuse` to `conf-libfuse3`.
- Rename generated libfuse flag files to `fuse3.cflags.sexp` and
  `fuse3.libs.sexp`.
- Update the `ocamlfuse3` package dependency from `conf-libfuse` to
  `conf-libfuse3`.
- Update conf package build checks and Linux depexts.
- Set first-version package availability to Linux-only.
- Regenerate opam files through Dune.

Exit criteria:

- A missing FUSE 3 development package fails with a clear message.
- With FUSE 3 installed, Dune reaches the C/API incompatibilities expected in
  later milestones.

Targeted verification:

```sh
pkg-config --atleast-version=3.10 fuse3
pkg-config --modversion fuse3
pkg-config --cflags --libs fuse3
dune build conf-libfuse3.opam ocamlfuse3.opam
dune build lib/fuse3.cflags.sexp lib/fuse3.libs.sexp
```

`dune build @install` is not an M1-only exit criterion unless M1 is bundled with
M2/M3, because switching discovery to libfuse 3 exposes the FUSE 3 C API
incompatibilities handled by the later milestones.

## M2: FUSE 3 Lifecycle Skeleton

Status: complete. See `m2-plan.md`.

Replace the libfuse 2 command-loop integration with a supported FUSE 3
lifecycle.

Tasks:

- Remove or replace `fuse_cmd`, `fuse_read_cmd`, `fuse_process_cmd`, and
  `fuse_exited` from `lib/Fuse_bindings.idl` and `lib/Fuse_util.c`.
- Set `FUSE_USE_VERSION` to `30`.
- Replace `ml_fuse_main` with a manual high-level lifecycle using
  `fuse_parse_cmdline`, `fuse_new`, `fuse_mount`, `fuse_daemonize`,
  `fuse_get_session`, `fuse_set_signal_handlers`, `fuse_loop`,
  `fuse_remove_signal_handlers`, `fuse_unmount`, and `fuse_destroy`.
- Force foreground and single-threaded behavior.
- Release the OCaml runtime while `fuse_loop` blocks.
- Keep callback wrappers responsible for acquiring the OCaml runtime before
  calling OCaml.
- Add temporary FUSE 3 callback ABI shims needed for compilation, while leaving
  final public API semantics to M3.
- Preserve the public `Fuse.main` return type while reporting setup failures
  with clear exceptions.

Exit criteria:

- `dune build @install` passes against libfuse 3.
- Mount setup and teardown errors are reported clearly.
- Public FUSE-3-shaped `Fuse.operations` and `Fuse.Fuse_compat` remain
  explicitly deferred to M3.

Verification:

```sh
tools/format_ocaml lib/Fuse.ml lib/Fuse.mli lib/Fuse_lib.ml
tools/format_c lib/Fuse_util.c lib/Unix_util_stubs.c
dune build @install
```

## M3: Existing Callback Parity

Status: complete. See `m3-plan.md`.

Port every currently implemented `Fuse.operations` callback to the FUSE 3
signature shape.

Tasks:

- Update `FOR_ALL_OPS`, operation closures, and callback macros in
  `lib/Fuse_util.c`.
- Update `lib/Fuse_bindings.idl` for any changed or removed C declarations.
- Implement the new FUSE-3-shaped `Fuse` API.
- Add nested `Fuse.Fuse_compat` with the old FUSE 2 shaped operations record.
- Replace `utime` with `utimens` in `Fuse`.
- Bridge `Fuse.Fuse_compat.utime` to `Fuse.utimens`.
- Keep `Fuse.ml` and `Fuse.mli` synchronized.

Exit criteria:

- All currently exposed operations compile against FUSE 3.
- The old API compiles through `Fuse.Fuse_compat`.
- Unsupported new parameters have documented behavior.
- No generated camlidl output is committed.

Verification:

```sh
tools/format_ocaml \
  lib/Fuse.ml lib/Fuse.mli lib/Fuse_lib.ml \
  example/hello.ml example/fusexmp.ml test/e2e/testfs.ml
tools/format_c lib/Fuse_util.c
dune build @install
dune build example/hello.exe example/fusexmp.exe
make test
```

## M4: Examples And e2e Tests

Update executable examples and the e2e suite to validate the FUSE 3 binding.

Tasks:

- Update `example/hello.ml` and `example/fusexmp.ml` for any public API changes.
- Update `test/e2e/testfs.ml` for any callback shape changes.
- Update the OUnit2 client for `utimens` and any intentionally unsupported FUSE
  3 behavior.
- Verify smoke and full e2e runs on a host with `/dev/fuse`.

Exit criteria:

- `make test` passes on a FUSE-capable Linux host.
- `make e2e` passes on a FUSE-capable Linux host.
- The skip path still works when FUSE is unavailable.

Verification:

```sh
dune build @install
make test
make e2e
OCAMLFUSE_E2E_REQUIRE_FUSE=1 make test
```

## M5: Documentation And Release Preparation

Update user and agent documentation to describe the completed FUSE 3 binding.

Tasks:

- Update `README.md` requirements and breaking changes.
- Update `docs/bindings.md` from libfuse 2 to libfuse 3.
- Update `AGENTS.md` project summary and binding workflow.
- Update package synopsis or descriptions if package names change.
- Archive this plan after implementation is complete.

Exit criteria:

- Documentation describes the current code rather than the migration process.
- Release notes identify public API changes, package changes, and runtime
  behavior.

Verification:

```sh
rg -n "libfuse 2|FUSE_USE_VERSION 26|pkg-config fuse|fuse_setup|fuse_cmd" README.md docs AGENTS.md lib
```

Any remaining matches must be intentional historical references or comments.

## M6: Multithreaded Loop Analysis

Analyze whether and how `ocamlfuse3` should support a multithreaded libfuse
event loop after the initial FUSE 3 lifecycle port is working.

Tasks:

- Compare libfuse 3.10 API-level `fuse_loop_mt(f, clone_fd)` with newer
  `fuse_loop_mt(f, config)` shapes, keeping the Jammy/libfuse 3.10 support
  constraint in mind.
- Determine whether FUSE-created worker threads must call
  `caml_c_thread_register` before acquiring the OCaml runtime.
- Decide how callbacks, `Thread_pool`, and OCaml domains interact if libfuse
  dispatches requests concurrently.
- Define user-facing controls for single-threaded versus multithreaded mode,
  if multithreading is supported.
- Update the e2e plan with at least one concurrency-oriented smoke test if
  multithreaded mode is implemented.

Exit criteria:

- A documented decision exists for whether `ocamlfuse3` supports
  multithreaded libfuse loops.
- If supported, the required C/OCaml runtime registration and cleanup model is
  specified before implementation.
- If not supported, the documentation explains that the FUSE 3 binding runs
  the high-level loop in single-threaded mode.

Verification:

```sh
rg -n "fuse_loop_mt|caml_c_thread_register|Thread_pool|single-thread|multithread" lib docs
```
