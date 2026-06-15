# M5 Plan: Documentation And Release Preparation

Status: complete; M5-specific decisions are closed in this plan.

Depends on M4, which is complete.

## Goal

Update user-facing, maintainer-facing, and package documentation so the
repository describes the current FUSE 3 binding rather than the old libfuse 2
state or the migration work that produced it.

M5 should make the repository understandable to a new user evaluating
`ocamlfuse3`, and to a maintainer preparing the first FUSE 3 release.

## Non-Goals

- Do not change the public OCaml API.
- Do not change FUSE lifecycle behavior.
- Do not add or remove callbacks.
- Do not implement multithreaded loop support; M6 owns that analysis.
- Do not archive `docs/plans/fuse3/` while M6 remains open.
- Do not hand-edit generated opam files except to verify generated output.

## Current State

The implementation has been migrated through M4:

- Build and package discovery target `pkg-config fuse3`.
- The public Dune and opam package name is `ocamlfuse3`.
- The local conf package name is `conf-libfuse3`.
- The top-level OCaml module remains `Fuse`.
- The native `Fuse` API is FUSE-3-shaped.
- `Fuse.Fuse_compat` preserves the old FUSE-2-shaped record as an upgrade aid.
- Examples and the mounted e2e filesystem use native `Fuse`.
- Mounted e2e verification passes on Linux with `/dev/fuse`.

The main stale documentation surfaces are:

- `README.md`, which still presents the old `ocamlfuse` package, libfuse 2
  requirement, libfuse 2 install package names, and multithreaded behavior.
- `docs/bindings.md`, which still describes libfuse 2 build flags,
  `fuse_setup`/`fuse_teardown`, and the removed command-loop integration.
- `dune-project` package description, which still says users can write
  multithreaded filesystems even though the current FUSE 3 loop is
  single-threaded.
- `AGENTS.md`, which still describes the repository as "migrating" instead of
  describing the current FUSE 3 codebase.

## Implementation Results

- `README.md` describes `ocamlfuse3`, libfuse 3 requirements, Linux support,
  build and test commands, examples, the native `Fuse` API, and
  `Fuse.Fuse_compat`.
- `docs/bindings.md` describes the current camlidl/libfuse 3 binding,
  generated `fuse3` flag files, FUSE 3 lifecycle, runtime behavior, and
  callback maintenance workflow.
- `docs/release-notes.md` documents the unreleased FUSE 3 migration, package
  changes, API changes, compatibility limits, runtime behavior, and mounted
  test requirements.
- `docs/README.md` links the release notes and reframes `docs/plans/fuse3/` as
  migration history plus remaining follow-up plans.
- `AGENTS.md` describes the repository as the current FUSE 3 binding instead
  of an active migration.
- `dune-project` and generated `ocamlfuse3.opam` describe FUSE 3 and no longer
  claim current multithreaded filesystem support.
- `conf-libfuse3.opam` did not change when opam files were regenerated.

## Implementation Checklist

1. Rewrite the active project overview in `README.md`:
   - use `ocamlfuse3` as the package name;
   - describe it as OCaml bindings for libfuse 3;
   - state Linux-only first-version support;
   - state the libfuse `>= 3.10` requirement;
   - mention `libfuse3-dev` for Debian and Ubuntu;
   - document `opam install ocamlfuse3`;
   - describe build, example, smoke, and full e2e commands;
   - explain that mounted tests require `/dev/fuse` access and mount
     permissions;
   - describe `Fuse` as the native FUSE 3 API and `Fuse.Fuse_compat` as the
     upgrade path;
   - replace old multithreaded claims with the current single-threaded loop
     behavior and point to M6 for multithreaded analysis;
   - preserve historical attribution in a short history section instead of
     keeping stale SourceForge-era installation and testing instructions as
     active guidance.
2. Update `docs/bindings.md`:
   - describe libfuse 3 and `FUSE_USE_VERSION 30`;
   - describe `pkg-config fuse3` and generated
     `fuse3.cflags.sexp`/`fuse3.libs.sexp`;
   - document the manual high-level lifecycle based on `fuse_parse_cmdline`,
     `fuse_new`, `fuse_mount`, `fuse_daemonize`, signal handlers, `fuse_loop`,
     `fuse_unmount`, and `fuse_destroy`;
   - document runtime release around `fuse_loop` and callback runtime
     acquisition;
   - include native `Fuse` and `Fuse.Fuse_compat` maintenance notes;
   - keep the callback-addition workflow aligned with the FUSE 3 API.
3. Add `docs/release-notes.md`:
   - create an "Unreleased FUSE 3 migration" section;
   - list package rename from `ocamlfuse` to `ocamlfuse3`;
   - list conf package rename from `conf-libfuse` to `conf-libfuse3`;
   - state libfuse 3 only and minimum libfuse `3.10`;
   - summarize native API breaking changes: `file_info`, `file_info_update`,
     `file_handle`, rename flags, readdir entries, and `utimens`;
   - document `Fuse.Fuse_compat` availability and limitations;
   - document current single-threaded foreground runtime behavior;
   - document mounted e2e coverage and FUSE access requirements.
4. Update `docs/README.md` to link release notes and identify
   `docs/plans/fuse3/` as migration planning rather than current user docs.
5. Update `AGENTS.md`:
   - describe the repository as the current FUSE 3 binding, not as actively
     migrating;
   - keep commands and layout aligned with the current code;
   - make the documentation guidance point to release notes and binding docs.
6. Update package descriptions in `dune-project`:
   - keep the package name `ocamlfuse3`;
   - remove the claim that the binding enables multithreaded filesystems;
   - mention FUSE 3 and zero-copy read/write buffers;
   - avoid implying libfuse 2 or dual-version support.
7. Regenerate opam files through Dune:
   - run `dune build conf-libfuse3.opam ocamlfuse3.opam`;
   - verify generated opam files match `dune-project` and templates.
8. Update FUSE 3 planning docs after implementation:
   - mark M5 complete in `m5-plan.md`, `README.md`, and `milestones.md`;
   - keep M6 visible as the remaining multithreaded-loop analysis;
   - do not archive the FUSE 3 planning directory until M6 is resolved.
9. Run documentation consistency checks.

## M5-Specific Decisions

| Topic | Decision | Reason |
| --- | --- | --- |
| README strategy | Rewrite active guidance around `ocamlfuse3`; keep old project history only as history | The current README has many libfuse 2 instructions that are misleading after M4. |
| Release notes location | Add `docs/release-notes.md` and link it from README/docs index | Release notes are easier to maintain separately from the general README and satisfy release-prep requirements. |
| Multithreaded claims | Remove user-facing multithreaded support claims for now | The FUSE 3 lifecycle currently uses `fuse_loop`; M6 will decide whether to support `fuse_loop_mt`. |
| Compatibility API documentation | Document `Fuse.Fuse_compat` as an upgrade aid, not the main API | Examples and e2e now use native `Fuse`; compat should not be the primary path for new code. |
| Migration plan archiving | Keep `docs/plans/fuse3/` active through M6 | M6 remains open, so archiving the whole FUSE 3 plan during M5 would hide active work. |
| Generated opam files | Regenerate through Dune, do not hand-edit | The generated files explicitly say to edit `dune-project` instead. |
| Historical migration docs | Allow historical libfuse 2 references inside `docs/plans/fuse3/` and `docs/plans/archived/` | Planning docs need to explain what changed; active docs should describe current behavior. |

## Documentation Targets

Active docs after M5 should communicate these facts:

- Users depend on `(libraries ocamlfuse3)` and `open Fuse`.
- The opam package is `ocamlfuse3`.
- The binding targets libfuse 3 only, with minimum libfuse `3.10`.
- The first supported platform target is Linux.
- The native API exposes FUSE 3 concepts such as `file_info`,
  `file_info_update`, `int64` file handles, rename flags, readdir flags,
  `dir_entry`, and `utimens` timestamps.
- `Fuse.Fuse_compat` offers the old operation record shape with documented
  limits: ignored new FUSE 3 parameters, `EINVAL` for unsupported nonzero
  rename flags, `EINVAL` for `Now`/`Omit` timestamp sentinels, and checked file
  handle conversion to `int`.
- The current FUSE loop is single-threaded and foreground-oriented.
- Mounted tests need Linux, `/dev/fuse`, and permissions to mount FUSE
  filesystems.

## Verification

These checks passed for M5:

```sh
dune build conf-libfuse3.opam ocamlfuse3.opam
dune build @install
dune build example/hello.exe example/fusexmp.exe
make e2e-smoke-test
```

`make e2e-smoke-test` passed outside the sandbox on a Linux host with `/dev/fuse` access.
The sandbox skip path was checked separately with `make e2e-smoke-test` inside the
sandbox, where `/dev/fuse` is unavailable. It printed `SKIP` and exited
successfully.

The active documentation stale-claim check passed:

```sh
rg -n \
  "libfuse 2|FUSE_USE_VERSION 26|pkg-config fuse([^3[:alnum:]_.-]|$)|fuse_setup|fuse_teardown|fuse_read_cmd|fuse_process_cmd|multithreaded filesystems|opam install ocamlfuse([^3[:alnum:]_-]|$)|libfuse-dev" \
  README.md docs/README.md docs/bindings.md docs/release-notes.md AGENTS.md dune-project ocamlfuse3.opam.template ocamlfuse3.opam
```

Result: no matches in active documentation or package descriptions.
Historical references may remain in `docs/plans/fuse3/`,
`docs/plans/archived/`, source comments, and release notes when explicitly
identified as history or migration notes.

These checks also passed:

```sh
rg -n "[ \t]+$" README.md docs AGENTS.md dune-project ocamlfuse3.opam.template
git diff --check
```
