# Agent Instructions

Scope: this file applies to the whole repository.

## Project

This repository builds `fuse3`, OCaml bindings for libfuse 3. The public
opam package and public Dune library are named `fuse3`; the local conf
package is `conf-libfuse3`; the internal Dune library name remains `fuse`.

The lifecycle implementation targets FUSE 3 with `FUSE_USE_VERSION 30` and a
manual high-level `fuse_new`/`fuse_mount` integration. The default runtime uses
libfuse's `fuse_loop_mt` and registers libfuse-created worker threads with the
OCaml runtime before invoking callbacks. Explicit `Fuse.Single_threaded` mode
uses `fuse_loop`, and FUSE `-s` also forces the single-threaded path. The public
OCaml callback API is FUSE-3-shaped. The legacy callback record shape is
available through the nested `Fuse.Fuse_compat` module for upgrade
compatibility.

The binding layer is generated with camlidl and completed by hand-written OCaml
and C glue. Treat the generated binding files as build artifacts and edit their
sources instead.

## Common Commands

- Build the library and install metadata: `dune build @install` or `make`.
- Run the FUSE 3 discovery checks:
  `dune build conf-libfuse3.opam fuse3.opam` and
  `dune build lib/fuse3.cflags.sexp lib/fuse3.libs.sexp`.
- Build the examples: `dune build example/hello.exe example/fusexmp.exe` or
  `make example`.
- Run unit tests and compile checks: `make test`.
- Run the default-mode smoke test: `make e2e-smoke-test`.
- Run the single-threaded smoke test: `make e2e-single-threaded-smoke-test`.
- Run the multithreaded smoke test: `make e2e-multithreaded-smoke-test`.
- Run the default-mode full end-to-end suite: `make e2e` or
  `test/e2e/run.sh full`.
- Run the single-threaded full end-to-end suite: `make e2e-single-threaded`.
- Run the multithreaded full end-to-end suite: `make e2e-multithreaded`.
- Format tracked OCaml sources: `tools/format_ocaml`.
- Format selected OCaml sources: `tools/format_ocaml path/to/file.ml
path/to/file.mli`.
- Format tracked C sources: `tools/format_c`.
- Format selected C sources: `tools/format_c path/to/file.c path/to/file.h`.
- Clean build artifacts: `dune clean` or `make clean`.

For non-documentation code changes, run `dune build @install` and `make test`.
Run build and test **sequentially** because `dune` uses a lock file that prevents
running more than one `dune` command in parallel.
For public API or example changes, also run the example build. For mounted FUSE
behavior changes, run `make e2e-smoke-test` outside the sandbox.
`make e2e-smoke-test` builds the e2e test binaries, then runs the smoke test
when FUSE is available. If FUSE is unavailable, it prints `SKIP` and exits
successfully. Set `OCAMLFUSE_E2E_REQUIRE_FUSE=1` to make missing FUSE support a
failure.
For loop-mode changes, also run the explicit single-threaded and multithreaded
e2e targets outside the sandbox.

The e2e tests (`make e2e-smoke-test`, `make e2e`,
`make e2e-single-threaded-smoke-test`, `make e2e-single-threaded`,
`make e2e-multithreaded-smoke-test`, `make e2e-multithreaded`) should be run
outside the sandbox, because inside the sandbox `/dev/fuse` is not accessible.

Running the examples mounts FUSE filesystems and requires a working libfuse
runtime, `/dev/fuse` access, and mount permissions. Do not assume those are
available in sandboxes or CI. If you run an example manually, use a temporary
mountpoint and unmount it afterwards with `fusermount -u` or the platform
equivalent.

## Repository Layout

- `lib/Fuse_bindings.idl`: camlidl source for low-level libfuse bindings.
- `lib/dune`: Dune rules that invoke camlidl and discover libfuse/camlidl link
  flags.
- `lib/config/discover.ml`: Dune configurator script. It queries `pkg-config`
  for `fuse3 >= 3.10` and uses `opam var camlidl:lib` or
  `ocamlfind query camlidl` for camlidl runtime linking.
- `lib/Fuse.ml` and `lib/Fuse.mli`: public OCaml API.
- `lib/Fuse_lib.ml`: callback registration helpers.
- `lib/Fuse_util.c`: hand-written C glue between FUSE callbacks and OCaml
  callbacks, including FUSE 3 file-info, rename, readdir, timestamp
  conversions, lifecycle loop dispatch, and libfuse worker-thread registration.
- `lib/Unix_util.ml` and `lib/Unix_util_stubs.c`: Unix helper bindings used by
  the library and examples.
- `example/`: small filesystems used as buildable examples.
- `test/e2e/`: Linux end-to-end tests. `testfs.ml` implements a temporary
  native `Fuse` backing filesystem, `client.ml` contains OUnit2 assertions,
  `xattr_stubs.c` provides Linux xattr, timestamp, and rename helpers,
  `compat_compile.ml` compile-checks `Fuse.Fuse_compat`, and `run.sh` mounts,
  tests, and cleans up. The default and explicit multithreaded full suites
  include a deterministic blocked-callback concurrency check.
- `tools/format_ocaml`: repository formatter wrapper for `.ml` and `.mli`
  files. It requires `ocamlformat` in `PATH`.
- `tools/format_c`: repository formatter wrapper for `.c` and `.h` files. It
  requires `clang-format` in `PATH`.
- `docs/`: agent-oriented project documentation. Start with
  `docs/README.md`.
- `docs/release-notes.md`: unreleased release notes for the FUSE 3 package.

## Binding Workflow

The Dune rule in `lib/dune` runs:

```sh
camlidl -header Fuse_bindings.idl
```

This generates `Fuse_bindings.h`, `Fuse_bindings_stubs.c`,
`Fuse_bindings.ml`, and `Fuse_bindings.mli` under the build directory. Do not
hand-edit generated versions of those files.

When adding or changing a FUSE operation, update all relevant hand-written
surfaces in lockstep:

- `lib/Fuse_bindings.idl` for the operation-name structure and external
  declarations.
- `lib/Fuse.ml` and `lib/Fuse.mli` for the public `operations` record,
  `default_operations`, `op_names_of_operations`, and any `Fuse.Fuse_compat`
  wrapper behavior.
- `lib/Fuse_util.c` for `FOR_ALL_OPS`, closure storage, callback argument
  conversion, result conversion, and the `struct fuse_operations` assignment.
- Examples and documentation when the public API changes.

Keep in mind that libfuse callback results are C errno values: OCaml callbacks
generally raise `Unix.Unix_error`, `Fuse_lib` converts them to
`Fuse_result.Bad`, and `Fuse_util.c` returns negative errno values to FUSE.

## C/OCaml Runtime Notes

- Use OCaml runtime macros (`CAMLparam`, `CAMLlocal`, `CAMLreturn`) for C stubs
  that allocate or touch OCaml values.
- Release the OCaml runtime around blocking C syscalls and reacquire it before
  constructing OCaml values.
- Preserve Bigarray buffer ownership semantics for read/write callbacks; the C
  layer exposes FUSE buffers as OCaml bigarrays without copying.
- Keep `Fuse.ml` and `Fuse.mli` synchronized for all public types and values.

## Style

- Keep edits focused and avoid unrelated reformatting.
- Run `tools/format_ocaml` after editing OCaml source files. Pass explicit
  `.ml` or `.mli` paths when only touched files should be formatted.
- Run `tools/format_c` after editing C source or header files. Pass explicit
  `.c` or `.h` paths when only touched files should be formatted.
- Preserve the GPL license header when adding source files that are part of the
  library implementation.
- Documentation files should be plain Markdown and should prefer concrete
  commands and file references over broad process advice.

## Documentation Guidelines

When updating the documentations, keep the docs descriptive of the current code
rather than describing the last modification or refactoring.
Use `docs/bindings.md` for binding architecture and maintenance details, and
`docs/release-notes.md` for user-visible package, API, runtime, and testing
changes.
