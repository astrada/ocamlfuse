# FUSE 3 Migration Plan

This directory tracks the planned migration from libfuse 2 to libfuse 3.

- `requirements.md`: migration goals, constraints, requirements, and decisions.
- `m0-checks.md`: completed M0 decision and environment checkpoint.
- `m1-plan.md`: detailed plan and accepted decisions for package/discovery
  changes.
- `api-delta.md`: known callback and lifecycle differences that affect the
  current binding.
- `public-api-proposal.md`: proposed OCaml representations for FUSE 3-specific
  public API values.
- `milestones.md`: staged implementation plan with exit criteria.

## Status

Planning. Core migration decisions are recorded in `requirements.md`; no
implementation has started in this directory.

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
