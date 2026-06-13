# Binding Architecture

`ocamlfuse3` exposes an OCaml API over libfuse 3. The low-level binding is
split between camlidl-generated code and hand-written OCaml and C glue.

The binding targets `FUSE_USE_VERSION 30` to stay compatible with libfuse
`3.10`, which is the minimum supported version for the first FUSE 3 release.

## Build-Time Generation

`lib/Fuse_bindings.idl` is the source for the camlidl-generated binding. During
the Dune build, `lib/dune` runs:

```sh
camlidl -header Fuse_bindings.idl
```

The generated `Fuse_bindings` C and OCaml files are produced inside `_build`.
Do not edit generated copies directly.

`lib/config/discover.ml` writes the generated `*.sexp` flag files consumed by
`lib/dune`:

- `fuse3.cflags.sexp` and `fuse3.libs.sexp` come from
  `pkg-config fuse3 >= 3.10`.
- `camlidl.libs.sexp` comes from `opam var camlidl:lib` or
  `ocamlfind query camlidl`.

The build intentionally requires `pkg-config fuse3`; it should not fall back to
linker flags that might use another FUSE version.

## Runtime Flow

1. User code builds a native `Fuse.operations` record and calls `Fuse.main`.
2. `Fuse.main` registers callback names with camlidl through
   `Fuse_bindings.set_fuse_operations`.
3. `Fuse_util.c` installs C callback functions in a `struct fuse_operations`.
4. `ml_fuse_main` parses FUSE command-line options, creates a high-level FUSE
   handle, mounts it, installs signal handlers, and enters `fuse_loop`.
5. libfuse calls the installed C callbacks.
6. The C callbacks acquire the OCaml runtime, convert arguments, call the
   registered OCaml callbacks, convert results or errors, then return libfuse
   status codes.
7. `ml_fuse_main` removes signal handlers, unmounts, destroys the FUSE handle,
   and releases parsed command-line resources.

The FUSE loop releases the OCaml runtime while blocked in `fuse_loop`, then
reacquires it before returning to OCaml. Callback wrappers are responsible for
acquiring the runtime before invoking OCaml callbacks.

The current runtime path uses the single-threaded high-level loop. The
multithreaded libfuse loop analysis is in
`docs/plans/fuse3/m6-analysis.md`; implementation is not started.

## Public API Shape

The top-level OCaml module is `Fuse`. Its native operation record follows the
FUSE 3 callback shape where the binding currently exposes a callback:

- `file_info` is passed to callbacks that receive `struct fuse_file_info`.
- `fopen` and `opendir` return `file_info_update`.
- file handles are `int64`.
- `rename` receives decoded rename flags and the raw flag value.
- `readdir` receives request flags and returns `dir_entry` values.
- `utimens` uses nanosecond timestamps and represents `UTIME_NOW` and
  `UTIME_OMIT` as `Now` and `Omit`.

`Fuse.Fuse_compat` exposes the old operation record shape as a nested module.
It is intended for incremental upgrades. Compatibility callbacks ignore new
file-info parameters where the old API had no place for them, reject unsupported
nonzero rename flags with `EINVAL`, reject timestamp sentinels that old `utime`
callbacks cannot represent, and convert file handles back to `int` with
overflow checks.

## Key Files

- `lib/Fuse_bindings.idl`: declares the generated C/OCaml binding surface and
  sets `FUSE_USE_VERSION 30`.
- `lib/config/discover.ml`: discovers libfuse 3 and camlidl runtime linker
  flags.
- `lib/Fuse_util.c`: owns FUSE lifecycle integration, callback wrappers, errno
  conversion, stat/statvfs conversion, xattr conversion, FUSE 3 file-info
  conversion, rename flag conversion, readdir conversion, and timestamp
  conversion.
- `lib/Fuse.ml` and `lib/Fuse.mli`: expose the native public operation record,
  `Fuse.main`, and the nested `Fuse.Fuse_compat` module.
- `lib/Fuse_lib.ml`: registers OCaml callbacks and maps exceptions to
  `Fuse_result`.
- `lib/Unix_util.ml` and `lib/Unix_util_stubs.c`: expose helper Unix bindings
  used by examples and filesystem implementations.
- `example/`: native `Fuse` examples.
- `test/e2e/`: mounted Linux e2e tests and the compile-only compatibility
  target.

## Adding A Callback

Adding a new libfuse callback normally requires changes in several places:

1. Add the callback name to `struct fuse_operation_names` in
   `lib/Fuse_bindings.idl`.
2. Add the callback to `type operations` in `lib/Fuse.ml` and `lib/Fuse.mli`.
3. Add the callback to `default_operations` and `op_names_of_operations`.
4. Add compatibility wrapper behavior in `Fuse.Fuse_compat` when the callback
   has an old API equivalent.
5. Add the callback to `FOR_ALL_OPS` in `lib/Fuse_util.c`.
6. Define the callback's argument, call, return, and result-conversion macros in
   `lib/Fuse_util.c`.
7. Assign the callback in the `struct fuse_operations` setup.
8. Update examples, e2e tests, and documentation when the public API changes.
9. Build with `dune build @install` to regenerate and compile the bindings.

Keep in mind that libfuse callback results are C errno values. OCaml callbacks
generally raise `Unix.Unix_error`, `Fuse_lib` converts callback results to
`Fuse_result`, and `Fuse_util.c` returns negative errno values to FUSE.
