# FUSE 3 API Delta

This document summarizes the libfuse 3 differences that affect the current
high-level binding. It is based on the official libfuse high-level API docs and
the current `lib/Fuse.ml`, `lib/Fuse.mli`, `lib/Fuse_bindings.idl`, and
`lib/Fuse_util.c`.

See `public-api-proposal.md` for the OCaml representations of FUSE 3-specific
values referenced below.

## Lifecycle Delta

Before M2, the binding used libfuse 2 lifecycle and command-loop internals:

- `fuse_setup`
- `fuse_teardown`
- `fuse_read_cmd`
- `fuse_process_cmd`
- `fuse_exited`
- `struct fuse_cmd`

The FUSE 3 high-level API documents lifecycle functions such as `fuse_mount`,
`fuse_loop`, `fuse_unmount`, `fuse_destroy`, and `fuse_get_session`. M2 replaced
the old command-loop integration with a supported FUSE 3 lifecycle.

The locally installed libfuse `3.14.0` headers provide:

- `fuse_main(argc, argv, op, private_data)` as a macro over `fuse_main_real`;
- `fuse_new(args, op, op_size, private_data)`;
- `fuse_mount(f, mountpoint)`;
- `fuse_loop(f)`;
- `fuse_loop_mt(f, config)` when `FUSE_USE_VERSION` is `312` or newer;
- `fuse_unmount(f)`;
- `fuse_destroy(f)`;
- `fuse_exit(f)`.

The same headers reject `FUSE_USE_VERSION` values below `30`.

The migration target is `FUSE_USE_VERSION 30` to support libfuse `3.10` on
Ubuntu Jammy and avoid dependencies on later FUSE API levels. The first version
should therefore avoid the FUSE 3.12+ `fuse_loop_mt(f, config)` API.

The M2 lifecycle implementation uses the design in `m2-plan.md`. The main
design points are:

- use a manual high-level lifecycle instead of `fuse_main`;
- force foreground operation for OCaml runtime safety;
- run single-threaded with `fuse_loop`;
- release the OCaml runtime while waiting in `fuse_loop`;
- keep callback wrappers responsible for acquiring the OCaml runtime before
  calling OCaml.

## Callback Delta

| Current OCaml operation | Current FUSE 2 shape | FUSE 3 shape | Initial migration policy |
| --- | --- | --- | --- |
| `init` | `struct fuse_conn_info *` | `struct fuse_conn_info *`, `struct fuse_config *`, returns private data | Keep `unit -> unit` in the first API; exposing conn/config can be a later additive API. |
| `getattr` | path, stat buffer | adds nullable `struct fuse_file_info *fi` | Expose `fi` option in `Fuse`; ignore in `Fuse.Fuse_compat`. |
| `readlink` | unchanged | unchanged | Preserve. |
| `mknod` | unchanged | unchanged | Preserve. |
| `mkdir` | unchanged | unchanged | Preserve. |
| `unlink` | unchanged | unchanged | Preserve. |
| `rmdir` | unchanged | unchanged | Preserve. |
| `symlink` | unchanged | unchanged | Preserve. |
| `rename` | old path, new path | adds `unsigned int flags` | Expose flags in `Fuse`; reject nonzero flags in `Fuse.Fuse_compat` unless old callback can represent them safely. |
| `link` | unchanged | unchanged | Preserve. |
| `chmod` | path, mode | adds nullable `struct fuse_file_info *fi` | Expose `fi` option in `Fuse`; ignore in `Fuse.Fuse_compat`. |
| `chown` | path, uid, gid | adds nullable `struct fuse_file_info *fi` | Expose `fi` option in `Fuse`; ignore in `Fuse.Fuse_compat`. |
| `truncate` | path, size | adds nullable `struct fuse_file_info *fi` | Expose `fi` option in `Fuse`; ignore in `Fuse.Fuse_compat`. |
| `utime` | path, atime, mtime | removed; FUSE 3 uses `utimens` | Expose `utimens` in `Fuse`; bridge old `utime` in `Fuse.Fuse_compat`. |
| `fopen` | path, `struct fuse_file_info *` | unchanged C callback name is still `open` | Preserve OCaml name `fopen` unless public API is redesigned. |
| `read` | unchanged | unchanged | Preserve. |
| `write` | unchanged | unchanged | Preserve. |
| `statfs` | unchanged | unchanged | Preserve. |
| `flush` | unchanged | unchanged | Preserve. |
| `release` | unchanged | unchanged | Preserve. |
| `fsync` | unchanged | unchanged | Preserve. |
| `setxattr` | unchanged | unchanged | Preserve. |
| `getxattr` | unchanged | unchanged | Preserve. |
| `listxattr` | unchanged | unchanged | Preserve. |
| `removexattr` | unchanged | unchanged | Preserve. |
| `opendir` | unchanged | unchanged | Preserve. |
| `readdir` | path, filler, offset, file info | adds `enum fuse_readdir_flags`; filler also takes fill flags | Expose readdir flags in `Fuse`; ignore request flags and pass default fill flags in `Fuse.Fuse_compat`. |
| `releasedir` | unchanged | unchanged | Preserve. |
| `fsyncdir` | unchanged | unchanged | Preserve. |

## New Or Previously Missing Callbacks

The current binding already lists several missing libfuse 2 callbacks. FUSE 3
also exposes additional high-level operations. These should be tracked as
post-migration enhancements unless required for compatibility:

- `destroy`
- `access`
- `create`
- `lock`
- `bmap`
- `ioctl`
- `poll`
- `write_buf`
- `read_buf`
- `flock`
- `fallocate`
- `copy_file_range`
- `lseek`
- `statx`

`utimens` is exposed in the new `Fuse` API because it replaces the old `utime`
behavior. The remaining callbacks are post-migration enhancements unless needed
to preserve existing behavior.

## e2e Coverage Implications

The existing e2e suite should remain the acceptance test for implemented
callbacks. It will need updates for:

- FUSE 3 mount behavior and options;
- `Fuse.utimens` and `Fuse.Fuse_compat.utime` bridging;
- rename flags in `Fuse` and intentional nonzero-flag behavior in
  `Fuse.Fuse_compat`;
- readdir flags in `Fuse` and default flag behavior in `Fuse.Fuse_compat`;
- any public API changes in the test filesystem.

If compatibility wrappers ignore new FUSE 3 parameters, the e2e suite should
also include at least one targeted test proving that unsupported non-default
behavior fails with an intentional errno rather than accidental behavior.
