# M8 Plan: Cleanup Pass

Status: complete.

Depends on M7, which added opt-in `fuse_loop_mt` support and split unit tests
from mounted e2e smoke tests.

## Goal

Do a focused cleanup pass after the FUSE 3 migration and multithreaded loop
work. The cleanup should reduce stale migration leftovers, remove unused code
where safe, and make build/test/package metadata match the current supported
shape.

M8 should not hide feature work behind cleanup. Runtime behavior, callback
semantics, and the public FUSE callback API should remain unchanged.

## Result

M8 raised the minimum OCaml version to `4.08.0`, removed the unused
`Thread_pool` module, cleaned stale callback-scope comments, and updated active
documentation for the post-M7 command layout. The implementation audit found
that `Thread_pool` was installed by Dune but was not documented as public API;
release notes now mention its removal.

## Scope

### Build And Test Commands

- Keep `make test` as the unit and compile-check target backed by
  `dune runtest`.
- Keep mounted smoke coverage under `make e2e-smoke-test`.
- Keep opt-in multithreaded mounted smoke coverage under
  `make e2e-multithreaded-smoke-test`.
- Check active documentation for stale `make test` references that imply a
  mounted FUSE run.

### Package Metadata

- Raise the minimum OCaml version to `4.08.0`.
- Update the requirement in `dune-project`.
- Regenerate and verify generated opam files through Dune.
- Update README requirements and release notes.
- Keep the public package and Dune public library name as `ocamlfuse3` for this
  milestone.

### Dead Code

- Audit and remove `lib/Thread_pool.ml` and `lib/Thread_pool.mli`.
- Keep the `threads` dependency and `-thread` build flag unless a build and
  runtime audit proves they are unnecessary. The FUSE 3 multithreaded path still
  depends on OCaml runtime thread support for foreign-thread callback entry.

### Source Comments And Small Hygiene

- Replace stale FUSE 2-era comments with FUSE 3-specific comments where they
  still describe current code.
- Remove or rewrite obsolete TODOs whose answer is now known after M3-M7.
- Leave nontrivial semantic TODOs in place when fixing them would change
  behavior or broaden the milestone.
- Keep `Fuse.ml` and `Fuse.mli` synchronized.
- Avoid broad rewrites of `Fuse_util.c`; touch C conversion helpers only when a
  comment or dead branch is clearly stale.

### Documentation

- Update active docs so they describe the current state after M7.
- Fix plan status drift, especially places that still say multithreaded support
  is not implemented.
- Keep historical libfuse 2 references inside migration plans when they explain
  past decisions.
- Update `docs/release-notes.md` for user-visible cleanup outcomes such as the
  OCaml minimum version change and any removed documented surface.

## Non-Goals

- Do not rename the package from `ocamlfuse3`.
- Do not add new FUSE callbacks.
- Do not change callback record shapes.
- Do not change default loop behavior.
- Do not make multithreading the default.
- Do not reintroduce a custom OCaml session loop.
- Do not make large C refactors that are unrelated to stale migration cleanup.

## Decisions

### Remove `Thread_pool`

Decision: remove `lib/Thread_pool.ml` and `lib/Thread_pool.mli` in M8.

Rationale: M6 concluded that libfuse owns worker-thread dispatch for the
supported multithreaded runtime. The module is not used by the FUSE 3 lifecycle,
and keeping it invites confusion about how multithreaded FUSE callbacks are
processed.

Risk: the module was installed by Dune, so removal could be observable if
external users depended on an undocumented compiled module directly. Release
notes mention the removal.

### Cleanup Depth

Decision: keep M8 to dead code, stale comments, metadata, and documentation
consistency.

Rationale: callback behavior and C conversion helpers are already covered by the
mounted e2e tests. Changing them during a cleanup pass would increase review
risk without improving the migration surface.

## Implementation Checklist

1. Check current references:

   ```sh
   rg -n "Thread_pool|make test|FUSE_USE_VERSION 26|fuse_read_cmd|fuse_process_cmd|fuse_setup|fuse_teardown" \
     lib test docs README.md AGENTS.md Makefile dune-project *.opam.template
   ```

2. Update package metadata:
   - `dune-project`
   - generated `ocamlfuse3.opam`
   - generated `conf-libfuse3.opam`, if Dune changes it
   - `README.md`
   - `docs/release-notes.md`

3. Remove `Thread_pool`:
   - delete `lib/Thread_pool.ml`
   - delete `lib/Thread_pool.mli`
   - verify no active source references remain
   - keep historical planning references only when they explain the M6 decision

4. Clean stale comments:
   - old FUSE 2 callback-version comments
   - comments that imply a custom or OCaml-owned request loop
   - comments that no longer match `fuse_loop`/`fuse_loop_mt` behavior

5. Update documentation:
   - `AGENTS.md`
   - `README.md`
   - `docs/bindings.md`
   - `docs/release-notes.md`
   - `docs/plans/fuse3/README.md`
   - `docs/plans/fuse3/milestones.md`
   - `docs/plans/fuse3/m6-analysis.md`
   - `docs/plans/fuse3/m7-plan.md`

6. Format touched source files:

   ```sh
   tools/format_ocaml <touched .ml/.mli files>
   tools/format_c <touched .c/.h files>
   ```

## Exit Criteria

- `make test` runs unit and compile checks only.
- Mounted smoke tests remain available through `make e2e-smoke-test`.
- OCaml package metadata requires OCaml `>= 4.08.0`.
- Active docs no longer describe M7 multithreaded support as future work.
- `Thread_pool` is removed.
- No generated camlidl files are committed.
- No public callback API changes are made.

## Verification

Run sequentially:

```sh
dune build conf-libfuse3.opam ocamlfuse3.opam
dune build @install
make test
dune build example/hello.exe example/fusexmp.exe
git diff --check
```

If any FUSE runtime files or e2e files change, also run mounted checks outside
the sandbox:

```sh
make e2e-smoke-test
make e2e-multithreaded-smoke-test
make e2e
```
