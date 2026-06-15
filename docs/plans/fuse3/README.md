# FUSE 3 Migration Plan

This directory tracks the planned migration from libfuse 2 to libfuse 3.

- `requirements.md`: migration goals, constraints, requirements, and decisions.
- `m0-checks.md`: completed M0 decision and environment checkpoint.
- `m1-plan.md`: detailed plan and accepted decisions for package/discovery
  changes.
- `m2-plan.md`: detailed plan and accepted decisions for the FUSE 3 lifecycle
  skeleton.
- `m3-plan.md`: completed plan and closed decisions for public API callback
  parity.
- `m4-plan.md`: completed plan and closed decisions for native examples and
  e2e tests.
- `m5-plan.md`: detailed plan and closed decisions for documentation and
  release preparation.
- `m6-analysis.md`: completed analysis and recommendations for opt-in
  multithreaded loop support.
- `m7-plan.md`: completed opt-in multithreaded loop implementation using
  libfuse's `fuse_loop_mt` and OCaml foreign-thread registration.
- `m8-plan.md`: completed cleanup pass for stale migration leftovers, package
  metadata, dead code, comments, and documentation consistency.
- `m9-plan.md`: completed public package rename from `ocamlfuse3` to `fuse3`.
- `m10-plan.md`: planned mounted e2e suite for the multithreaded loop mode.
- `ocaml-libfuse3-bindings.md`: supplemental external-analysis notes about
  libfuse-created threads and OCaml runtime registration.
- `api-delta.md`: known callback and lifecycle differences that affect the
  current binding.
- `public-api-proposal.md`: OCaml representations for FUSE 3-specific public
  API values.
- `milestones.md`: staged implementation plan with exit criteria.

## Status

M0 through M9 are complete. M10 is planned.

## Primary References

- libfuse high-level operations:
  <https://libfuse.github.io/doxygen/structfuse__operations.html>
- libfuse high-level API:
  <https://libfuse.github.io/doxygen/fuse_8h.html>
- libfuse common API:
  <https://libfuse.github.io/doxygen/fuse__common_8h.html>

## Local Discovery Notes

The current development environment exposes:

- libfuse 2 through `pkg-config fuse`, reporting version `2.9.9`;
- libfuse 3 through `pkg-config fuse3`, reporting version `3.14.0`.

`pkg-config --cflags --libs fuse3` reports:

```sh
-I/usr/include/fuse3 -lfuse3 -lpthread
```

The installed libfuse 3 headers are available under `/usr/include/fuse3`.
