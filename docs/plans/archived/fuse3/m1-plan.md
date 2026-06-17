# M1 Plan: Build And Package Discovery

Status: complete.

Depends on M0, which is complete.

## Goal

Switch the repository's build and packaging discovery from libfuse 2 to libfuse
3 without yet porting the C callback/lifecycle implementation.

M1 is intentionally about package identity and dependency discovery. It does not
make the full library build green by itself unless it is implemented together
with M2/M3.

## Expected File Changes

- `dune-project`
- `conf-libfuse.opam.template` renamed to `conf-libfuse3.opam.template`
- `ocamlfuse.opam.template` renamed to `ocamlfuse3.opam.template`
- generated `conf-libfuse.opam` replaced by generated `conf-libfuse3.opam`
- generated `ocamlfuse.opam` replaced by generated `ocamlfuse3.opam`
- `lib/config/discover.ml`
- `lib/dune`
- `example/dune`
- `test/e2e/dune`
- FUSE 3 planning docs as needed

## Implementation Checklist

1. Rename package stanzas in `dune-project`:
   - `conf-libfuse` to `conf-libfuse3`
   - `ocamlfuse` to `ocamlfuse3`
2. Update the `ocamlfuse3` package dependency from `conf-libfuse` to
   `conf-libfuse3`.
3. Rename opam template files to match the new package names.
4. Update `conf-libfuse3.opam.template`:
   - check `pkg-config --atleast-version 3.10 fuse3`;
   - use FUSE 3 development depexts;
   - remove macFUSE depexts for the first Linux-only version.
5. Update `ocamlfuse3.opam.template`:
   - keep repository URLs unless the repository is renamed;
   - set Linux-only availability.
6. Update `lib/config/discover.ml`:
   - query `pkg-config fuse3`;
   - fail clearly when `fuse3.pc` is missing;
   - fail clearly when the version is below `3.10`;
   - do not silently fall back to libfuse 2;
   - write libfuse 3 C flags and link flags for Dune.
7. Update `lib/dune`:
   - change `(public_name ocamlfuse)` to `(public_name ocamlfuse3)`;
   - update generated flag filenames to `fuse3.cflags.sexp` and
     `fuse3.libs.sexp`.
8. Update internal consumers:
   - `example/dune` should link `ocamlfuse3`;
   - `test/e2e/dune` should link `ocamlfuse3`.
9. Regenerate opam files through Dune.
10. Remove the old generated opam files after the new generated files exist.

## Accepted Decisions

| Topic | Recommendation | Reason |
| --- | --- | --- |
| Public Dune library name | Use `ocamlfuse3` | Users should depend on `(libraries ocamlfuse3)` while still opening module `Fuse`. |
| Internal Dune library name | Keep `(name fuse)` | Minimizes churn; the public name is what users see. |
| Generated flag filenames | Rename to `fuse3.cflags.sexp` and `fuse3.libs.sexp` | Makes build artifacts reflect the target C library. |
| `pkg-config` fallback | Make `pkg-config fuse3` mandatory | libfuse 3 needs the include path from `fuse3.pc`; fallback risks unclear compile failures or accidental libfuse 2 usage. |
| Package availability | Use Linux-only availability for first version | macOS/macFUSE and BSD are out of scope for the first FUSE 3 release. |
| Non-Debian depexts | Add best-effort FUSE 3 names, verify before release | Debian/Ubuntu is required; other distributions can be corrected before publishing. |
| Repository URLs | Keep existing URLs for M1 | Package naming can change before repository hosting changes. |

## M1-Specific Decisions

- M1 may be used as a standalone branch checkpoint where targeted
  package/discovery checks pass but `dune build @install` still fails until
  M2/M3. Do not merge or release M1 alone unless it is bundled with M2/M3.
- The public Dune library name becomes `ocamlfuse3`; the internal Dune library
  name remains `(name fuse)`.
- Generated libfuse flag files are renamed to `fuse3.cflags.sexp` and
  `fuse3.libs.sexp`.
- The first `ocamlfuse3` opam package is Linux-only.

## Depext Proposal

Use these initial depexts for `conf-libfuse3`:

```opam
depexts: [
  ["libfuse3-dev"] {os-family = "debian" | os-distribution = "ubuntu"}
  ["fuse3-dev"] {os-distribution = "alpine"}
  ["fuse3-devel"] {os-distribution = "centos"}
  ["fuse3-devel"] {os-family = "fedora"}
  ["fuse3-devel"] {os-distribution = "ol"}
  ["fuse3-devel"] {os-family = "suse" | os-family = "opensuse"}
  ["fuse3"] {os-family = "arch"}
]
```

Only Debian/Ubuntu is part of the hard M1 support target because Ubuntu Jammy is
the minimum platform requirement. The other names should be verified before
publishing.

## Verification

Run these checks for M1:

```sh
pkg-config --atleast-version=3.10 fuse3
pkg-config --modversion fuse3
pkg-config --cflags --libs fuse3
dune build conf-libfuse3.opam ocamlfuse3.opam
```

Build generated FUSE 3 flag files:

```sh
dune build lib/fuse3.cflags.sexp lib/fuse3.libs.sexp
```

Then check that libfuse 2 package/discovery names no longer appear in active
build metadata:

```sh
rg -n "conf-libfuse([^3[:alnum:]_-]|$)|pkg-config fuse([^3[:alnum:]_.-]|$)|public_name ocamlfuse\)|libraries ocamlfuse([ )]|$)" \
  dune-project lib example test *.opam *.opam.template
```

Expected result: no active build metadata should still refer to the libfuse 2
package names or `pkg-config fuse`.

`dune build @install` is not an M1-only exit criterion unless M1 is bundled with
M2/M3, because switching to libfuse 3 discovery exposes FUSE 3 C API
incompatibilities that are intentionally handled later.

## Verification Result

The M1 targeted checks pass locally with libfuse `3.14.0`.

`dune build @install` reaches the expected FUSE 3 API incompatibilities for
later milestones, including `FUSE_USE_VERSION` below `30`, removed `utime`,
changed callback signatures, and removed `fuse_setup`/`fuse_teardown`.
