# Public API Representation Proposal

This proposal fills in the remaining OCaml representation details for the
FUSE-3-shaped `Fuse` module.

The proposal favors:

- explicit records over raw integers where the FUSE meaning is stable;
- raw fields alongside decoded flags where future or platform-specific bits may
  appear;
- prefixed record labels to avoid collisions with existing `operations` record
  fields such as `flush`, `read`, and `write`;
- `int64` for C `uint64_t` values, treated as opaque bit patterns when needed.

## `struct fuse_file_info`

Represent incoming `struct fuse_file_info` values as an immutable OCaml record:

```ocaml
type file_handle = int64

type file_info = {
  fi_flags : Unix.open_flag list;
  fi_flags_raw : int;
  fi_fh : file_handle;
  fi_writepage : bool;
  fi_direct_io : bool;
  fi_keep_cache : bool;
  fi_flush : bool;
  fi_nonseekable : bool;
  fi_flock_release : bool;
  fi_cache_readdir : bool;
  fi_noflush : bool;
  fi_lock_owner : int64;
  fi_poll_events : int32;
}
```

Use `file_info option` for FUSE 3 callbacks where the C `fi` pointer may be
`NULL`, such as `getattr`, `chmod`, `chown`, `truncate`, and `utimens`.

Represent changes that OCaml may request from `open` and `opendir` with a
separate update record:

```ocaml
type file_info_update = {
  fi_update_fh : file_handle option;
  fi_update_direct_io : bool;
  fi_update_keep_cache : bool;
  fi_update_nonseekable : bool;
  fi_update_cache_readdir : bool;
  fi_update_noflush : bool;
}

val default_file_info_update : file_info_update
```

`file_info_update` should be returned by `fopen` and `opendir`. The C wrapper
applies only fields that are meaningful for the callback:

- `fi_update_fh` maps to `fi->fh` when present.
- `fi_update_direct_io`, `fi_update_keep_cache`, `fi_update_nonseekable`, and
  `fi_update_noflush` are meaningful for `fopen`.
- `fi_update_cache_readdir` is meaningful for `opendir`.

`Fuse.Fuse_compat` should convert the old `int option` file handle API to and
from `file_handle` with checked `Int64.of_int` and `Int64.to_int` conversions.

For M3, expose the compatibility API as the nested module `Fuse.Fuse_compat`.
The library is wrapped and `Fuse.ml` is the root module, so this avoids changing
Dune wrapping or exposing internal modules as public top-level modules. After
`open Fuse`, callers can still refer to `Fuse_compat`.

## Rename Flags

Represent FUSE 3 rename flags as a decoded record plus raw bit mask:

```ocaml
type rename_flags = {
  rename_noreplace : bool;
  rename_exchange : bool;
  rename_whiteout : bool;
  rename_flags_raw : int;
}
```

Rationale:

- `RENAME_NOREPLACE` and `RENAME_EXCHANGE` are documented by the libfuse 3
  high-level API.
- `RENAME_WHITEOUT` is Linux-specific and may not be available on every target,
  but exposing the field keeps Linux behavior visible.
- `rename_flags_raw` preserves unknown or future bits.

`Fuse.rename` should receive `rename_flags`. `Fuse.Fuse_compat.rename` should
call the old two-argument callback only when `rename_flags_raw = 0`; otherwise
it should return `EINVAL` unless a more precise compatibility behavior is
chosen.

## Readdir Flags And Entries

Represent request flags passed to `readdir` as:

```ocaml
type readdir_flags = {
  readdir_plus : bool;
  readdir_flags_raw : int;
}
```

Represent filler flags and returned directory entries as:

```ocaml
type fill_dir_flags = {
  fill_dir_plus : bool;
}

type dir_entry = {
  entry_name : string;
  entry_stats : Unix.LargeFile.stats option;
  entry_offset : int64 option;
  entry_flags : fill_dir_flags;
}
```

Mapping policy:

- `entry_stats = None` maps to a `NULL` stat pointer.
- `entry_offset = None` maps to offset `0`, preserving the current stateless
  readdir style.
- `entry_flags.fill_dir_plus = true` maps to `FUSE_FILL_DIR_PLUS`.
- `Fuse.Fuse_compat.readdir` ignores `readdir_flags` and returns entries with no
  stats, no offset, and default fill flags.

This shape preserves the current simple `string list` compatibility path while
letting the FUSE 3 API support `FUSE_READDIR_PLUS`.

## Timespec And `utimens`

Represent `struct timespec` and `utimensat` sentinel values as:

```ocaml
type timespec = {
  tv_sec : int64;
  tv_nsec : int;
}

type timestamp =
  | Time of timespec
  | Now
  | Omit
```

`Time` should enforce `0 <= tv_nsec < 1_000_000_000` before crossing into C.
`Now` maps to `UTIME_NOW`, and `Omit` maps to `UTIME_OMIT`.

The FUSE 3 operation should be shaped as:

```ocaml
utimens : string -> timestamp -> timestamp -> file_info option -> unit
```

The first timestamp is atime and the second is mtime.

`Fuse.Fuse_compat` should call the old
`utime : string -> float -> float -> unit` callback when both FUSE 3 timestamps
are concrete `Time` values. It should reject `Now` or `Omit` with `EINVAL`
because the old callback cannot represent timestamp sentinels. The compatibility
path may lose precision compared with direct `Fuse.utimens` usage.

## First API Surface Sketch

The first FUSE-3-shaped `operations` record should include only callbacks needed
to replace current behavior:

```ocaml
type operations = {
  init : unit -> unit;
  getattr : string -> file_info option -> Unix.LargeFile.stats;
  readlink : string -> string;
  mknod : string -> int -> unit;
  mkdir : string -> int -> unit;
  unlink : string -> unit;
  rmdir : string -> unit;
  symlink : string -> string -> unit;
  rename : string -> string -> rename_flags -> unit;
  link : string -> string -> unit;
  chmod : string -> int -> file_info option -> unit;
  chown : string -> int -> int -> file_info option -> unit;
  truncate : string -> int64 -> file_info option -> unit;
  utimens : string -> timestamp -> timestamp -> file_info option -> unit;
  fopen : string -> file_info -> file_info_update;
  read : string -> buffer -> int64 -> file_info -> int;
  write : string -> buffer -> int64 -> file_info -> int;
  statfs : string -> Unix_util.statvfs;
  flush : string -> file_info -> unit;
  release : string -> file_info -> unit;
  fsync : string -> bool -> file_info -> unit;
  setxattr : string -> string -> string -> xattr_flags -> unit;
  getxattr : string -> string -> string;
  listxattr : string -> string list;
  removexattr : string -> string -> unit;
  opendir : string -> file_info -> file_info_update;
  readdir : string -> int64 -> file_info -> readdir_flags -> dir_entry list;
  releasedir : string -> file_info -> unit;
  fsyncdir : string -> bool -> file_info -> unit;
}
```

`init` can stay `unit -> unit` in the first FUSE 3 release because the current
binding does not expose connection configuration. Exposing `struct
fuse_conn_info`, `struct fuse_config`, or private data can be a later additive
API once there is a concrete use case.
