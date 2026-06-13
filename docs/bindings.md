# Binding Architecture

`ocamlfuse` exposes an OCaml API over libfuse 2. The low-level binding is split
between camlidl-generated code and hand-written glue.

## Build-Time Generation

`lib/Fuse_bindings.idl` is the source for the camlidl-generated binding. During
the Dune build, `lib/dune` runs `camlidl -header Fuse_bindings.idl` and produces
the generated `Fuse_bindings` C and OCaml files inside `_build`.

`lib/config/discover.ml` writes the generated `*.sexp` flag files consumed by
`lib/dune`:

- `fuse.cflags.sexp` and `fuse.libs.sexp` come from `pkg-config fuse`, with a
  fallback to `-lfuse`.
- `camlidl.libs.sexp` comes from `opam var camlidl:lib` or
  `ocamlfind query camlidl`.

## Runtime Flow

1. User code builds a `Fuse.operations` record and calls `Fuse.main`.
2. `Fuse.main` registers callback names with camlidl through
   `Fuse_bindings.set_fuse_operations`.
3. `Fuse_util.c` installs C callback functions in a `struct fuse_operations`.
4. libfuse calls those C callbacks.
5. The C callbacks acquire the OCaml runtime, convert arguments, call the
   registered OCaml callbacks, convert results or errors, then return libfuse
   status codes.
6. `Fuse_lib.fuse_loop` reads and processes FUSE commands. In multithreaded
   mode it dispatches work through `Thread_pool`.

## Key Files

- `lib/Fuse_bindings.idl`: declares the generated C/OCaml binding surface.
- `lib/Fuse_util.c`: owns FUSE callback wrappers, errno conversion, stat/statvfs
  conversion, xattr conversion, and `fuse_setup`/`fuse_teardown` integration.
- `lib/Fuse.ml` and `lib/Fuse.mli`: expose the public operation record and
  `main`.
- `lib/Fuse_lib.ml`: registers OCaml callbacks and maps exceptions to
  `Fuse_result`.
- `lib/Unix_util.ml` and `lib/Unix_util_stubs.c`: expose helper Unix bindings
  used by examples and filesystem implementations.

## Adding A Callback

Adding a new libfuse callback normally requires changes in several places:

1. Add the callback name to `struct fuse_operation_names` in
   `lib/Fuse_bindings.idl`.
2. Add the callback to `type operations` in `lib/Fuse.ml` and `lib/Fuse.mli`.
3. Add the callback to `default_operations` and `op_names_of_operations`.
4. Add the callback to `FOR_ALL_OPS` in `lib/Fuse_util.c`.
5. Define the callback's argument, call, return, and result-conversion macros in
   `lib/Fuse_util.c`.
6. Build with `dune build @install` to regenerate and compile the bindings.

For public API changes, update examples or documentation so downstream users can
see the intended OCaml shape of the callback.
