# Release Notes

## Unreleased FUSE 3 Migration

This release moves the binding to libfuse 3 and renames the public package.

## Package Changes

- The opam and public Dune package is now `ocamlfuse3`.
- The conf package is now `conf-libfuse3`.
- The build requires libfuse 3 with minimum version `3.10`.
- The first supported platform target is Linux.
- Build discovery uses `pkg-config fuse3` and does not fall back to another
  FUSE package.

## Public API Changes

The top-level OCaml module remains `Fuse`, but the main `Fuse.operations`
record now follows the FUSE 3 callback shape for the callbacks implemented by
the binding.

Notable native API changes include:

- callbacks such as `getattr`, `chmod`, `chown`, `truncate`, and `utimens`
  receive optional `file_info`;
- `fopen` and `opendir` return `file_info_update`;
- file handles are represented as `int64`;
- `rename` receives decoded rename flags and the raw flag value;
- `readdir` receives request flags and returns `dir_entry` values;
- `utimens` replaces the old float timestamp callback and uses nanosecond
  timestamps plus `Now` and `Omit` sentinels.

## Compatibility API

`Fuse.Fuse_compat` remains available as a nested module for incremental
upgrades. It exposes the older operation record shape while running through the
FUSE 3 implementation.

Compatibility limits are intentional:

- new file-info parameters are ignored where the older callback shape cannot
  represent them;
- unsupported nonzero rename flags raise `Unix.Unix_error` with `EINVAL`;
- `Now` and `Omit` timestamp sentinels raise `Unix.Unix_error` with `EINVAL`
  when bridged to the older float timestamp callback;
- file handles are converted back to `int` with overflow checks.

## Runtime Behavior

The current runtime uses the high-level single-threaded `fuse_loop` path. The
binding keeps the FUSE process foreground-oriented and releases the OCaml
runtime while blocked in the FUSE loop. Callback wrappers reacquire the runtime
before calling OCaml callbacks.

Support for the libfuse worker-thread loop remains unimplemented. The current
analysis recommends adding it only as an explicit opt-in mode.

## Tests

`make test` runs the mounted smoke suite when FUSE is available. `make e2e`
runs the full mounted suite, including coverage for the native FUSE 3 callback
shape, xattrs, `utimens`, and rename flags.

Mounted tests require Linux, `/dev/fuse`, and permission to mount FUSE
filesystems. Without FUSE access, the smoke suite prints `SKIP` unless
`OCAMLFUSE_E2E_REQUIRE_FUSE=1` is set.
