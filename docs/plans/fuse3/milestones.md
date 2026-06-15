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
make e2e-smoke-test
```

## M4: Examples And e2e Tests

Status: complete. See `m4-plan.md`.

Update executable examples and the e2e suite to validate the FUSE 3 binding.

Tasks:

- Update `example/hello.ml` and `example/fusexmp.ml` to use native `Fuse`
  rather than `Fuse.Fuse_compat`.
- Update `test/e2e/testfs.ml` to use native `Fuse` and the FUSE 3 callback
  shapes.
- Update the OUnit2 client for `utimens` and any intentionally unsupported FUSE
  3 behavior.
- Add a compile-only compatibility target so `Fuse.Fuse_compat` remains checked
  after examples and e2e migrate to native `Fuse`.
- Verify smoke and full e2e runs on a host with `/dev/fuse`.

Exit criteria:

- Examples and the mounted e2e filesystem compile against native `Fuse`.
- Only the compile-only compatibility target uses `Fuse.Fuse_compat`.
- `make e2e-smoke-test` passes on a FUSE-capable Linux host.
- `make e2e` passes on a FUSE-capable Linux host.
- The skip path still works when FUSE is unavailable.

Verification:

```sh
tools/format_ocaml \
  example/hello.ml example/fusexmp.ml \
  test/e2e/testfs.ml test/e2e/client.ml test/e2e/compat_compile.ml
tools/format_c test/e2e/xattr_stubs.c
dune build @install
dune build example/hello.exe example/fusexmp.exe
dune build test/e2e/testfs.exe test/e2e/client.exe test/e2e/compat_compile.exe
make e2e-smoke-test
make e2e
OCAMLFUSE_E2E_REQUIRE_FUSE=1 make e2e-smoke-test
```

## M5: Documentation And Release Preparation

Status: complete. See `m5-plan.md`.

Update user and agent documentation to describe the completed FUSE 3 binding.

Tasks:

- Update `README.md` requirements and breaking changes.
- Update `docs/bindings.md` from libfuse 2 to libfuse 3.
- Update `AGENTS.md` project summary and binding workflow.
- Update package synopsis or descriptions if package names change.
- Add release notes for the FUSE 3 migration.
- Keep the FUSE 3 planning directory active until M6 is complete.

Exit criteria:

- Documentation describes the current code rather than the migration process.
- Release notes identify public API changes, package changes, and runtime
  behavior.

Verification:

```sh
rg -n \
  "libfuse 2|FUSE_USE_VERSION 26|pkg-config fuse([^3[:alnum:]_.-]|$)|fuse_setup|fuse_teardown|fuse_read_cmd|fuse_process_cmd|multithreaded filesystems|opam install ocamlfuse([^3[:alnum:]_-]|$)|libfuse-dev" \
  README.md docs/README.md docs/bindings.md docs/release-notes.md AGENTS.md dune-project ocamlfuse3.opam.template ocamlfuse3.opam
```

Expected result: no matches in active documentation or package descriptions.
Historical references may remain in migration plans and archived plans when
explicitly identified as historical context.

## M6: Multithreaded Loop Analysis

Status: analysis complete; implementation followed in M7. See
`m6-analysis.md`.

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
  multithreaded libfuse loops: support only as an explicit opt-in mode.
- If supported, the required C/OCaml runtime registration and cleanup model is
  specified before implementation: use per-thread registration for libfuse
  worker threads with pthread TLS cleanup.
- If not supported, the documentation explains that the FUSE 3 binding runs
  the high-level loop in single-threaded mode.

Verification:

```sh
rg -n "fuse_loop_mt|caml_c_thread_register|Thread_pool|single-thread|multithread" lib docs
```

## M7: Opt-In libfuse Multithreaded Loop

Status: complete. See `m7-plan.md`.

Implement opt-in multithreaded support with libfuse's high-level
`fuse_loop_mt(fuse, opts.clone_fd)` path and OCaml foreign-thread registration.

Tasks:

- Add public `loop_mode = Single_threaded | Multi_threaded`.
- Add `?loop_mode` to `Fuse.main` and `Fuse.Fuse_compat.main`.
- Extend `ml_fuse_main` to receive the requested loop mode.
- Preserve the existing `fuse_loop` path for effective `Single_threaded`.
- Use `fuse_loop_mt(fuse, opts.clone_fd)` for effective `Multi_threaded`.
- Keep FUSE `-s` as a force-single-thread override.
- Add pthread TLS markers for OCaml-owned versus binding-registered threads.
- Register libfuse worker threads with `caml_c_thread_register` before
  acquiring the OCaml runtime.
- Unregister binding-registered worker threads from a pthread-key destructor.
- Add a mounted multithreaded smoke target.

Exit criteria:

- Existing calls to `Fuse.main argv ops` and `Fuse.Fuse_compat.main argv ops`
  compile unchanged.
- Explicit `~loop_mode:Single_threaded` behaves like the current default.
- Explicit `~loop_mode:Multi_threaded` routes through `fuse_loop_mt`.
- Libfuse-created callback threads are registered with the OCaml runtime before
  running OCaml callbacks.
- Mounted single-threaded and multithreaded smoke tests pass on a FUSE-capable
  Linux host.

Verification:

```sh
tools/format_ocaml lib/Fuse.ml lib/Fuse.mli test/e2e/testfs.ml test/unit/*.ml
tools/format_c lib/Fuse_util.c
dune build conf-libfuse3.opam ocamlfuse3.opam
dune build @install
dune build example/hello.exe example/fusexmp.exe
make e2e-smoke-test
make e2e-multithreaded-smoke-test
make e2e
```

## M8: Cleanup Pass

Status: complete. See `m8-plan.md`.

Clean up stale migration leftovers after M7 without changing runtime behavior or
the public FUSE callback API.

Tasks:

- Keep `make test` as the unit and compile-check target.
- Keep mounted smoke coverage under `make e2e-smoke-test`.
- Raise the minimum OCaml version to `4.08.0`.
- Audit and remove `lib/Thread_pool.ml` and `lib/Thread_pool.mli`.
- Remove or rewrite stale FUSE 2-era comments that no longer describe the
  current FUSE 3 binding.
- Update active docs and release notes so they match the post-M7 state.

Exit criteria:

- `make test` runs unit and compile checks only.
- Mounted smoke tests remain available through `make e2e-smoke-test`.
- Package metadata and README require OCaml `>= 4.08.0`.
- Active docs no longer describe M7 multithreaded support as future work.
- `Thread_pool` is removed.
- No public callback API changes are made.

Verification:

```sh
dune build conf-libfuse3.opam ocamlfuse3.opam
dune build @install
make test
dune build example/hello.exe example/fusexmp.exe
git diff --check
```

Run mounted checks outside the sandbox if runtime or e2e files change:

```sh
make e2e-smoke-test
make e2e-multithreaded-smoke-test
make e2e
```

## M9: Rename Public Package To `fuse3`

Status: planned. See `m9-plan.md`.

Rename the public Dune library and opam package from `ocamlfuse3` to `fuse3`
while keeping the OCaml module name `Fuse`, the internal Dune library name
`fuse`, and the conf package name `conf-libfuse3`.

Tasks:

- Rename the package stanza in `dune-project` to `fuse3`.
- Rename `ocamlfuse3.opam.template` to `fuse3.opam.template`.
- Regenerate `fuse3.opam` and remove `ocamlfuse3.opam`.
- Update `lib/dune` to expose `(public_name fuse3)`.
- Update repo-local Dune dependencies in examples and tests.
- Update active README, AGENTS, binding docs, and release notes.

Exit criteria:

- `dune-project` defines package `fuse3`.
- `lib/dune` exposes public library `fuse3`.
- `fuse3.opam` is generated.
- Examples and tests depend on `(libraries fuse3 ...)`.
- The OCaml module remains `Fuse`.
- The conf package remains `conf-libfuse3`.
- No runtime behavior changes are made.

Verification:

```sh
dune build conf-libfuse3.opam fuse3.opam
dune build @install
make test
dune build example/hello.exe example/fusexmp.exe
dune build test/e2e/testfs.exe test/e2e/client.exe test/e2e/compat_compile.exe
git diff --check
```
