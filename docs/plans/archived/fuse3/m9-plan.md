# M9 Plan: Rename Public Package To `fuse3`

Status: complete.

Depends on M8, which completed the post-FUSE-3 cleanup pass.

## Goal

Rename the public Dune library and opam package from `ocamlfuse3` to `fuse3`.
The OCaml module name must remain `Fuse`, and the internal Dune library name
should remain `fuse`.

This milestone is package identity work. It should not change FUSE callback
semantics, runtime behavior, examples, or the public OCaml module shape.

## Result

M9 renamed the public opam package and public Dune library to `fuse3`. The
internal Dune library remains `fuse`, the OCaml module remains `Fuse`, the conf
package remains `conf-libfuse3`, and no `ocamlfuse3` alias package was added.

## Decisions

- Public opam package name: `fuse3`.
- Public Dune library name: `fuse3`.
- Top-level OCaml module name: keep `Fuse`.
- Internal Dune library name: keep `(name fuse)`.
- Local conf package name: keep `conf-libfuse3`.
- C library discovery files: keep `fuse3.cflags.sexp` and `fuse3.libs.sexp`.
- Compatibility module: keep `Fuse.Fuse_compat`.

## Scope

### Build Metadata

- Rename the package stanza in `dune-project` from `ocamlfuse3` to `fuse3`.
- Rename `ocamlfuse3.opam.template` to `fuse3.opam.template`.
- Regenerate opam files so `fuse3.opam` is produced.
- Remove the generated `ocamlfuse3.opam` file after `fuse3.opam` exists.
- Update `lib/dune` from `(public_name ocamlfuse3)` to
  `(public_name fuse3)`.
- Update `lib/config/discover.ml`'s configurator name from `ocamlfuse3` to
  `fuse3`.

### Reverse Dependencies Inside The Repo

- Update example and test Dune files from `(libraries ocamlfuse3 ...)` to
  `(libraries fuse3 ...)`.
- Update any documentation command that builds generated package files:
  `dune build conf-libfuse3.opam fuse3.opam`.
- Keep source code references to the OCaml module `Fuse` unchanged.

### Documentation

- Update active user and agent docs:
  - `README.md`
  - `AGENTS.md`
  - `docs/bindings.md`
  - `docs/release-notes.md`
  - `docs/README.md`, if needed
- Update active FUSE 3 planning docs where they describe the current target
  package name.
- Keep historical `ocamlfuse3` references in older milestone docs when they
  explain the prior package-name decision.
- Add release notes for the second package rename from `ocamlfuse3` to `fuse3`.

### Compatibility

- Do not add an `ocamlfuse3` alias package in this milestone.
- Do not keep two public Dune library names in this repository.
- Before publishing, check opam-repository for name availability and decide
  whether a transitional `ocamlfuse3` package is needed outside this source
  tree.

## Non-Goals

- Do not rename the repository.
- Do not rename the OCaml module from `Fuse`.
- Do not rename `conf-libfuse3`.
- Do not rename generated libfuse flag files.
- Do not change callback records or runtime loop behavior.
- Do not add deprecation shims or alias libraries unless a later release plan
  requires them.

## Implementation Checklist

1. Rename package metadata:

   ```sh
   mv ocamlfuse3.opam.template fuse3.opam.template
   ```

   Then update `dune-project` and `lib/dune`.

2. Update repo-local Dune dependencies:
   - `example/dune`
   - `test/e2e/dune`
   - `test/unit/dune`

3. Update active docs and commands:
   - README install command: `opam install fuse3`
   - Dune build commands: `dune build conf-libfuse3.opam fuse3.opam`
   - AGENTS common commands and package summary
   - binding docs package name
   - release notes package-change section

4. Regenerate package files:

   ```sh
   dune build conf-libfuse3.opam fuse3.opam
   ```

5. Remove stale generated package files:
   - `ocamlfuse3.opam`

6. Scan active metadata and docs:

   ```sh
   rg -n "ocamlfuse3|libraries ocamlfuse3|public_name ocamlfuse3|opam install ocamlfuse3" \
     README.md AGENTS.md docs/README.md docs/bindings.md docs/release-notes.md \
     dune-project lib example test *.opam *.opam.template
   ```

   Expected result: no matches in active metadata, active user docs, examples,
   or tests except release-note entries that explicitly describe the rename.
   Historical matches may remain in `docs/plans/fuse3/`.

## Exit Criteria

- `dune-project` defines package `fuse3`.
- `lib/dune` exposes public library `fuse3`.
- `fuse3.opam` is generated.
- `ocamlfuse3.opam` and `ocamlfuse3.opam.template` are removed.
- Examples and tests depend on `(libraries fuse3 ...)`.
- Active docs tell users to install and link `fuse3`.
- The OCaml module remains `Fuse`.
- The conf package remains `conf-libfuse3`.
- No runtime behavior changes are made.

## Verification

Run sequentially:

```sh
dune build conf-libfuse3.opam fuse3.opam
dune build @install
make test
dune build example/hello.exe example/fusexmp.exe
dune build test/e2e/testfs.exe test/e2e/client.exe test/e2e/compat_compile.exe
git diff --check
```

Mounted FUSE checks are not required for the rename alone because M9 changes
package metadata and compile-time dependencies, not runtime behavior.
