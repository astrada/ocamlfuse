# M11 Plan: Default To Multithreaded Loop Mode

Status: planned; decisions accepted; ready to implement.

Depends on M10, which added full mounted e2e coverage for
`Fuse.Multi_threaded`, including a deterministic blocked-callback concurrency
test.

## Goal

Switch the public default runtime from single-threaded `fuse_loop` to
libfuse's multithreaded `fuse_loop_mt`.

After M11, existing calls such as:

```ocaml
Fuse.main argv ops
Fuse.Fuse_compat.main argv compat_ops
```

should use multithreaded mode by default. Users who need old behavior should
pass `~loop_mode:Single_threaded` or pass FUSE `-s`.

This milestone intentionally changes default runtime behavior. It should not
change callback record shapes, the `loop_mode` type, or the supported libfuse
version target.

## Current State

- `Fuse.main` defaults `?loop_mode` to `Single_threaded`.
- `Fuse.Fuse_compat.main` forwards its optional `?loop_mode` to `Fuse.main`.
- `test/e2e/run.sh` defaults `OCAMLFUSE_E2E_LOOP_MODE` to `single`.
- The default mounted e2e targets run with `-s`.
- Explicit multithreaded coverage is available through:
  - `make e2e-multithreaded-smoke-test`
  - `make e2e-multithreaded`
- FUSE `-s` already forces the effective path back to single-threaded mode.

## Accepted Decisions

### Public API Default

Decision: change only the default value of `Fuse.main ?loop_mode` from
`Single_threaded` to `Multi_threaded`.

Rationale: the public control surface added in M7 remains sufficient. Existing
source continues to compile, but runtime behavior changes to the new default.
Users retain an explicit `~loop_mode:Single_threaded` escape hatch.

`Fuse.Fuse_compat.main` should inherit the same default by continuing to forward
the optional argument rather than defining a separate default.

### FUSE `-s`

Decision: keep FUSE `-s` as a force-single-thread override.

Rationale: `-s` is a standard FUSE option and remains the clearest operational
escape hatch. If user code requests or defaults to `Multi_threaded`, passing
`-s` should still route to `fuse_loop`.

### e2e Runner Loop Modes

Decision: add a third e2e loop mode named `default`.

`test/e2e/run.sh` should accept:

- `default`
- `single`
- `multi`

and default to `default`.

In `default` mode:

- `test/e2e/testfs.ml` should call `Fuse.main Sys.argv test_operations`
  without `~loop_mode`;
- the runner should not pass `-s`;
- the mounted tests should therefore exercise the public default.

In `single` mode:

- `testfs.ml` should call `Fuse.main ~loop_mode:Single_threaded`;
- the runner should pass `-s` to keep testing the command-line override.

In `multi` mode:

- `testfs.ml` should call `Fuse.main ~loop_mode:Multi_threaded`;
- the runner should not pass `-s`.

### Makefile Targets

Decision: reinterpret the default e2e targets as default-mode coverage and add
explicit single-threaded targets.

Targets after M11:

- `make e2e-smoke-test`: mounted smoke suite using the public default.
- `make e2e`: full mounted suite using the public default.
- `make e2e-single-threaded-smoke-test`: mounted smoke suite with
  `OCAMLFUSE_E2E_LOOP_MODE=single`.
- `make e2e-single-threaded`: full mounted suite with
  `OCAMLFUSE_E2E_LOOP_MODE=single`.
- `make e2e-multithreaded-smoke-test`: explicit mounted smoke suite with
  `OCAMLFUSE_E2E_LOOP_MODE=multi`.
- `make e2e-multithreaded`: explicit full mounted suite with
  `OCAMLFUSE_E2E_LOOP_MODE=multi`.

Rationale: after the default changes, `make e2e` should test the public default
rather than legacy single-threaded behavior. Explicit single-threaded targets
keep coverage for the escape hatch and FUSE `-s` override.

### Concurrency Test Placement

Decision: run the M10 concurrency test in both `default` and explicit `multi`
full suites, and not in explicit `single` mode.

Rationale: the default full suite should prove that the new default is actually
multithreaded. Explicit `multi` remains useful as a direct regression target.
Single-threaded mode is expected to serialize the blocked callback and the
independent request, so it should not run this test.

## Implementation Checklist

1. Update `lib/Fuse.ml`:
   - change `let main ?(loop_mode = Single_threaded)` to default to
     `Multi_threaded`;
   - keep `Fuse.Fuse_compat.main ?loop_mode` forwarding unchanged.

2. Update unit/compile checks:
   - keep explicit `Single_threaded` and `Multi_threaded` compile checks;
   - add a simple default-call check if one is not already present.

3. Update `test/e2e/run.sh`:
   - accept `default|single|multi`;
   - default `OCAMLFUSE_E2E_LOOP_MODE` to `default`;
   - pass `-s` only for `single`.

4. Update `test/e2e/testfs.ml`:
   - represent e2e loop selection as `Default | Explicit of Fuse.loop_mode`;
   - call `Fuse.main` without `~loop_mode` for `default`;
   - keep explicit single and multi paths.

5. Update `test/e2e/client.ml`:
   - treat `loop_mode = "default"` like `"multi"` for the concurrency test;
   - keep the concurrency test disabled for `"single"`.

6. Update `Makefile`:
   - add explicit single-threaded smoke and full targets;
   - keep existing explicit multithreaded targets;
   - make `e2e-smoke-test` and `e2e` use default mode.

7. Update documentation:
   - `README.md`
   - `AGENTS.md`
   - `docs/bindings.md`
   - `docs/release-notes.md`
   - `docs/plans/fuse3/milestones.md`
   - this plan's status/result section

## Non-Goals

- Do not remove `Single_threaded`.
- Do not remove FUSE `-s` support.
- Do not change callback record shapes.
- Do not expose max-thread controls.
- Do not change the libfuse `3.10` / `FUSE_USE_VERSION 30` compatibility
  target.
- Do not make mounted tests part of `make test`.

## Exit Criteria

- `Fuse.main argv ops` defaults to `fuse_loop_mt`.
- `Fuse.Fuse_compat.main argv ops` defaults to `fuse_loop_mt`.
- Explicit `~loop_mode:Single_threaded` still routes through `fuse_loop`.
- FUSE `-s` still forces `fuse_loop`.
- Default mounted smoke and full e2e targets exercise the public default.
- Explicit single-threaded mounted targets cover the legacy path.
- Explicit multithreaded mounted targets still pass.
- Active docs describe multithreaded mode as the default and single-threaded
  mode as the opt-out.

## Verification

Run sequentially:

```sh
tools/format_ocaml lib/Fuse.ml test/e2e/testfs.ml test/e2e/client.ml test/unit/*.ml
dune build @install
make test
dune build test/e2e/testfs.exe test/e2e/client.exe test/e2e/compat_compile.exe
git diff --check
```

Run mounted checks outside the sandbox:

```sh
make e2e-smoke-test
make e2e
make e2e-single-threaded-smoke-test
make e2e-single-threaded
make e2e-multithreaded-smoke-test
make e2e-multithreaded
OCAMLFUSE_E2E_REQUIRE_FUSE=1 make e2e
OCAMLFUSE_E2E_REQUIRE_FUSE=1 make e2e-single-threaded
```
