# FUSE 3 Migration Requirements

## Goal

Update `ocamlfuse` from libfuse 2 to libfuse 3 while keeping the binding
maintainable, testable, and clear about any public API breakage.

The FUSE 3 package will be named `ocamlfuse3` and will support only libfuse 3.
It will not preserve libfuse 2 build support.

The migration must preserve the existing camlidl-based generation model unless
an implementation milestone proves that camlidl cannot represent the required
FUSE 3 surface safely.

## Current State

The repository is partway through the libfuse 3 migration:

- Build and package discovery target libfuse 3 through `pkg-config fuse3`.
- `conf-libfuse3.opam` checks `pkg-config --atleast-version=3.10 fuse3`.
- The public opam and Dune package is `ocamlfuse3`.
- The internal Dune library remains `fuse`, so the OCaml top-level module is
  still `Fuse`.
- Generated libfuse flag files are named `fuse3.cflags.sexp` and
  `fuse3.libs.sexp`.
- The callback and lifecycle implementation still need the FUSE 3 port:
  `lib/Fuse_bindings.idl` defines `FUSE_USE_VERSION 26` and includes
  `<fuse.h>`.
- `lib/Fuse_util.c` uses libfuse 2 lifecycle functions and command-loop types,
  including `fuse_setup`, `fuse_teardown`, `fuse_read_cmd`,
  `fuse_process_cmd`, `fuse_exited`, and `struct fuse_cmd`.
- The public OCaml API exposes a FUSE 2 shaped `Fuse.operations` record.
- The e2e suite mounts a test filesystem and validates the currently implemented
  callbacks.

## Target Requirements

### Build And Packaging

- The build must discover libfuse 3 with `pkg-config fuse3`.
- Do not silently fall back to libfuse 2 discovery or linker flags.
- Dune-generated flag files should stay isolated behind
  `lib/config/discover.ml`.
- The opam and Dune package name must be `ocamlfuse3`.
- The local conf package must be renamed from `conf-libfuse` to
  `conf-libfuse3`.
- The `ocamlfuse3` opam metadata must depend on `conf-libfuse3`.
- `conf-libfuse3` must check `pkg-config --atleast-version=3.10 fuse3`.
- Linux depexts need to be updated to FUSE 3 development packages, for example
  `libfuse3-dev` on Debian and Ubuntu.
- The minimum supported libfuse 3 version is `3.10`, matching Ubuntu Jammy.
- The build must fail with a clear message when libfuse 3 headers or
  `fuse3.pc` are unavailable.
- The generated opam files must continue to be generated from `dune-project`.

### C And camlidl Binding Surface

- `FUSE_USE_VERSION` must move from `26` to `30`.
- `FUSE_USE_VERSION 30` is the recommended target because it is the broadest
  libfuse 3 API level and avoids depending on APIs added after Ubuntu Jammy's
  libfuse `3.10`.
- The implementation must not depend on FUSE API `312` or newer. In particular,
  do not require the FUSE 3.12+ `fuse_loop_mt(f, config)` API in the first
  version.
- The IDL and hand-written C glue must include the libfuse 3 headers provided by
  `pkg-config fuse3`.
- Generated camlidl files must remain build artifacts; agents should edit
  `lib/Fuse_bindings.idl` and hand-written glue, not generated outputs.
- The FUSE lifecycle must stop relying on removed libfuse 2 command-loop
  internals.
- The new lifecycle must preserve OCaml runtime safety:
  - do not let libfuse daemonize after OCaml runtime startup on OCaml 5;
  - release the OCaml runtime while the FUSE loop blocks;
  - acquire the OCaml runtime before invoking OCaml callbacks;
  - preserve cleanup on loop exit, mount failure, and signal-driven shutdown.

### Public OCaml API

- The main public API should be FUSE-3-shaped. OCaml callbacks should expose
  FUSE 3 concepts where practical, including file info, rename flags, readdir
  flags, and nanosecond timestamps.
- Add a `Fuse_compat` module that exposes the old FUSE 2 shaped API on top of
  libfuse 3 to ease upgrades for existing users.
- The default assumption is that module `Fuse` becomes the FUSE 3 API and
  module `Fuse_compat` provides the old `Fuse.operations` shape.
- The OCaml top-level module name remains `Fuse` for the FUSE 3 API.
- Public API changes must update both `lib/Fuse.ml` and `lib/Fuse.mli`.
- `Fuse` must expose `utimens`, because FUSE 3 no longer exposes the old
  `utime` callback.
- `Fuse_compat` should bridge the old `utime : string -> float -> float -> unit`
  callback to `utimens`, with documented precision loss.
- Any ignored FUSE 3 parameter must have a documented policy. Examples:
  - ignore nullable `struct fuse_file_info *fi` for compatibility wrappers;
  - return `EINVAL` or `ENOSYS` for unsupported nonzero rename flags;
  - ignore `FUSE_READDIR_PLUS` until attributes are exposed in `readdir`.
- The migration must document that `ocamlfuse3` supports only libfuse 3.

### Callback Coverage

- The first complete FUSE 3 version must support all callbacks currently
  implemented by `Fuse.operations`, except where a FUSE 3 replacement is
  explicitly documented.
- New libfuse 3 callbacks such as `create`, `destroy`, `access`, `fallocate`,
  `copy_file_range`, `lseek`, and `statx` are not required in the first
  complete version unless needed to preserve existing behavior.
- The first public API should include only callbacks needed to replace current
  behavior. `utimens` is included because it replaces current `utime` behavior.
- Unsupported optional callbacks should remain absent rather than stubbed with
  misleading behavior.

### Testing

- `dune build @install` must compile against libfuse 3.
- `make test` must run the smoke e2e suite against a mounted FUSE 3 filesystem.
- `make e2e` must run the full e2e suite against FUSE 3 and cover every
  implemented callback.
- The e2e harness must continue to skip cleanly when FUSE access is unavailable
  unless `OCAMLFUSE_E2E_REQUIRE_FUSE=1` is set.
- At least one verification pass must run outside the sandbox on a host with
  `/dev/fuse` access.

### Documentation And Release

- `README.md` must describe the FUSE 3 requirement and any public API breakage.
- `docs/bindings.md` and `AGENTS.md` must be updated after implementation so
  they describe the new binding, not this migration process.
- Package descriptions and conf package names must not imply libfuse 2 support
  if the package becomes FUSE 3 only.
- The release notes must call out mount/runtime behavior on OCaml 5.

## Non-Goals For The First Complete Version

- Binding the low-level FUSE API.
- Implementing every optional libfuse 3 callback.
- Supporting libfuse 2.
- Supporting Windows.
- Adding macOS/macFUSE support unless explicitly chosen before implementation.
- Replacing camlidl unless required by a concrete blocker.

## Decisions

- The repository targets libfuse 3 only for this migration.
- The minimum supported libfuse 3 version is `3.10`, for Ubuntu Jammy support.
- `FUSE_USE_VERSION` should be `30` unless implementation proves a blocker.
- The Dune/opam package name is `ocamlfuse3`.
- The local conf package name is `conf-libfuse3`.
- The main public API should be FUSE-3-shaped.
- The OCaml top-level module name remains `Fuse` for the FUSE 3 API.
- A `Fuse_compat` module should provide the old FUSE 2 shaped API on top of
  libfuse 3 for upgrade compatibility.
- The first public API includes only callbacks needed to replace current
  behavior.

## Proposed Design Details

See `public-api-proposal.md` for proposed OCaml representations of
`struct fuse_file_info`, rename flags, readdir flags, and `struct timespec`.
