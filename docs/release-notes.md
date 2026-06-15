# Release Notes

## Unreleased FUSE 3 Migration

This release moves the binding to libfuse 3 and renames the public package.

## Package Changes

- The opam and public Dune package is now `fuse3`.
- The conf package is now `conf-libfuse3`.
- The build requires libfuse 3 with minimum version `3.10`.
- The build requires OCaml `>= 4.08.0`.
- The first supported platform target is Linux.
- Build discovery uses `pkg-config fuse3` and does not fall back to another
  FUSE package.
- The previously installed but unused `Thread_pool` module has been removed.
  Multithreaded execution uses libfuse worker threads through
  `~loop_mode:Multi_threaded`.
- The `ocamlfuse3` package name used during migration planning has been renamed
  to `fuse3` before release; this repository does not ship an `ocamlfuse3`
  alias package.

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
- `Fuse.main` and `Fuse.Fuse_compat.main` accept `?loop_mode`, defaulting to
  `Single_threaded`.

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

The default runtime uses the high-level single-threaded `fuse_loop` path. The
binding keeps the FUSE process foreground-oriented and releases the OCaml
runtime while blocked in the FUSE loop.

Users can opt into libfuse's worker-thread loop with
`~loop_mode:Multi_threaded`. In that mode the binding calls `fuse_loop_mt` and
registers libfuse-created worker threads with the OCaml runtime before running
OCaml callbacks. FUSE `-s` still forces the single-threaded path.

## Tests

`make test` runs unit and compile checks. `make e2e-smoke-test` runs the
mounted smoke suite when FUSE is available. `make e2e` runs the full mounted
suite, including coverage for the native FUSE 3 callback shape, xattrs,
`utimens`, and rename flags. `make e2e-multithreaded-smoke-test` runs the
mounted smoke suite with opt-in multithreaded mode.

Mounted tests require Linux, `/dev/fuse`, and permission to mount FUSE
filesystems. Without FUSE access, the smoke suite prints `SKIP` unless
`OCAMLFUSE_E2E_REQUIRE_FUSE=1` is set.
