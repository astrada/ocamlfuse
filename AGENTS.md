# Agent Instructions

Scope: this file applies to the whole repository.

## Project

This repository builds `ocamlfuse`, OCaml bindings for libfuse 2
(`FUSE_USE_VERSION 26`). The public opam package and public Dune library are
named `ocamlfuse`; the internal Dune library name is `fuse`.

The binding layer is generated with camlidl and completed by hand-written OCaml
and C glue. Treat the generated binding files as build artifacts and edit their
sources instead.

## Common Commands

- Build the library and install metadata: `dune build @install` or `make`.
- Build the examples: `dune build example/hello.exe example/fusexmp.exe` or
  `make example`.
- Run the smoke test: `make test`.
- Run the full end-to-end suite: `make e2e` or `test/e2e/run.sh full`.
- Format tracked OCaml sources: `tools/format_ocaml`.
- Format selected OCaml sources: `tools/format_ocaml path/to/file.ml
  path/to/file.mli`.
- Clean build artifacts: `dune clean` or `make clean`.

For non-documentation code changes, run `dune build @install` and `make test`.
For public API or example changes, also run the example build. `make test`
builds the e2e test binaries, then runs the smoke test when FUSE is available.
If FUSE is unavailable, it prints `SKIP` and exits successfully. Set
`OCAMLFUSE_E2E_REQUIRE_FUSE=1` to make missing FUSE support a failure.

Running the examples mounts FUSE filesystems and requires a working libfuse 2
runtime, `/dev/fuse` access, and mount permissions. Do not assume those are
available in sandboxes or CI. If you run an example manually, use a temporary
mountpoint and unmount it afterwards with `fusermount -u` or the platform
equivalent.

## Repository Layout

- `lib/Fuse_bindings.idl`: camlidl source for low-level libfuse bindings.
- `lib/dune`: Dune rules that invoke camlidl and discover libfuse/camlidl link
  flags.
- `lib/config/discover.ml`: Dune configurator script. It queries `pkg-config`
  for `fuse` and uses `opam var camlidl:lib` or `ocamlfind query camlidl` for
  camlidl runtime linking.
- `lib/Fuse.ml` and `lib/Fuse.mli`: public OCaml API.
- `lib/Fuse_lib.ml`: callback registration and FUSE command loop dispatch.
- `lib/Fuse_util.c`: hand-written C glue between FUSE callbacks and OCaml
  callbacks.
- `lib/Unix_util.ml` and `lib/Unix_util_stubs.c`: Unix helper bindings used by
  the library and examples.
- `example/`: small filesystems used as buildable examples.
- `test/e2e/`: Linux end-to-end tests. `testfs.ml` implements a temporary
  backing filesystem, `client.ml` contains OUnit2 assertions, `xattr_stubs.c`
  provides Linux xattr helpers, and `run.sh` mounts, tests, and cleans up.
- `tools/format_ocaml`: repository formatter wrapper for `.ml` and `.mli`
  files. It requires `ocamlformat` in `PATH`.
- `docs/`: agent-oriented project documentation. Start with
  `docs/README.md`.

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
  `default_operations`, and `op_names_of_operations`.
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
- Follow the existing C formatting style for C sources.
- Preserve the GPL license header when adding source files that are part of the
  library implementation.
- Documentation files should be plain Markdown and should prefer concrete
  commands and file references over broad process advice.

## Documentation Guidelines

When updating the documentations, keep the docs descriptive of the current code
rather than describing the last modification or refactoring.
