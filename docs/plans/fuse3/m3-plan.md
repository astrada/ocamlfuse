# M3 Plan: Existing Callback Parity And Public API

Status: planned; M3-specific decisions closed in this plan.

Depends on M2, which is complete.

## Goal

Replace the temporary M2 callback ABI shims with the real FUSE-3-shaped public
`Fuse.operations` API, while providing a compatibility module for the old
FUSE-2-shaped operation record.

M3 should make `dune build @install` pass with the new public API. Updating the
examples and e2e filesystem to use the new API remains M4 unless a small
compile-only compatibility check is added during M3.

## Non-Goals

- Do not add optional FUSE 3 callbacks beyond those needed to replace current
  behavior.
- Do not add multithreaded loop support; M6 covers that analysis.
- Do not update the e2e behavior suite beyond any small compile-only check
  needed to prove `Fuse.Fuse_compat` compiles.
- Do not commit generated camlidl files.

## Current M2 State

M2 uses FUSE 3 lifecycle and `FUSE_USE_VERSION 30`, but the public OCaml API is
still FUSE-2-shaped. `lib/Fuse_util.c` contains temporary compatibility shims
for changed FUSE 3 callbacks, including:

- `utimens` calling the old OCaml `utime` callback;
- `rename` rejecting nonzero flags;
- file-info callbacks ignoring `struct fuse_file_info *`;
- `readdir` ignoring request flags and using default filler flags.

M3 replaces those shims with conversions for the new public types.

## Expected File Changes

- `lib/Fuse.ml`
- `lib/Fuse.mli`
- `lib/Fuse_lib.ml`
- `lib/Fuse_bindings.idl`
- `lib/Fuse_util.c`
- FUSE 3 planning docs as needed

Do not add a separate `lib/Fuse_compat.ml` in the first implementation pass.
The compatibility API should live as a nested module in `Fuse.ml`/`Fuse.mli`.

## Implementation Checklist

1. Add public FUSE 3 types to `Fuse.ml` and `Fuse.mli`:
   - `file_handle = int64`;
   - `file_info`;
   - `file_info_update`;
   - `default_file_info_update`;
   - `rename_flags`;
   - `readdir_flags`;
   - `fill_dir_flags`;
   - `dir_entry`;
   - `timespec`;
   - `timestamp`.
2. Replace the public `operations` record with the FUSE-3-shaped record from
   `public-api-proposal.md`.
3. Update callback registration in `Fuse.op_names_of_operations`:
   - use arity wrappers that match the new callbacks;
   - register `utimens`, not the old `utime` label;
   - preserve `fopen` as the OCaml name for C `open`.
4. Update `lib/Fuse_bindings.idl`:
   - remove the M2 `mlname(utime)` compatibility label for `utimens`;
   - keep the operation-name structure aligned with `struct fuse_operations`;
   - avoid adding generated camlidl outputs to version control.
5. Add C conversion helpers in `lib/Fuse_util.c`:
   - convert `struct fuse_file_info *` to `file_info`;
   - apply `file_info_update` back to `struct fuse_file_info *` for `open` and
     `opendir`;
   - decode rename flags, readdir flags, and filler flags;
   - convert OCaml `dir_entry` values into `fuse_fill_dir_t` calls;
   - convert `struct timespec` and `UTIME_NOW`/`UTIME_OMIT` to OCaml
     `timestamp`;
   - validate OCaml `Time` nanoseconds before any C-side conversion.
6. Update C callback wrappers to the FUSE 3 public API:
   - `init` remains `unit -> unit` and returns `NULL`;
   - `getattr`, `chmod`, `chown`, `truncate`, and `utimens` pass
     `file_info option`;
   - `rename` passes `rename_flags`;
   - `fopen` and `opendir` return `file_info_update`;
   - `read`, `write`, `flush`, `release`, `fsync`, `releasedir`, and
     `fsyncdir` pass `file_info`;
   - `readdir` passes offset, file info, and request flags, and consumes
     `dir_entry list`.
7. Add the nested compatibility module:
   - expose `module Fuse_compat : sig ... end` from `Fuse`;
   - define the old FUSE-2-shaped `operations` record;
   - define old-shaped `default_operations`;
   - define old-shaped `main`;
   - implement compatibility by wrapping old callbacks into new
     `Fuse.operations`.
8. Implement compatibility conversion policies:
   - ignore nullable `file_info` where old callbacks cannot represent it;
   - convert old `int option` file handles to `file_info_update`;
   - convert new `file_handle` values back to `int` with range checks;
   - reject unsupported nonzero rename flags with `EINVAL`;
   - ignore `readdir_flags` and return simple string entries with no stats,
     offset, or fill flags;
   - convert old float `utime` values to `Time` timestamps.
9. Keep `Fuse.ml` and `Fuse.mli` synchronized.
10. Update planning docs with implementation results after M3 is complete.

## M3-Specific Decisions

| Topic | Decision | Reason |
| --- | --- | --- |
| Compatibility module placement | Expose `Fuse.Fuse_compat` as a nested module | The library is wrapped and `Fuse.ml` is the root module. A separate top-level `Fuse_compat` would require changing Dune wrapping or adding another public library. After `open Fuse`, users can refer to `Fuse_compat`. |
| Separate `Fuse_compat.ml` file | Do not add one for M3 | A separate module would need to depend on the root `Fuse` API, while `Fuse.ml` would need to expose it, creating an awkward dependency cycle. Keep the first version nested. |
| Public `Fuse` API | Make `Fuse.operations` FUSE-3-shaped | This follows the accepted migration direction and removes the M2 temporary shim semantics from the main API. |
| Old API | Preserve old shape in `Fuse.Fuse_compat` | Existing users get an explicit upgrade path without keeping the main API FUSE-2-shaped. |
| File handles | Use `int64` in `Fuse`; checked `int` conversions in `Fuse.Fuse_compat` | FUSE uses `uint64_t` handles. The old API used `int`, so compatibility must fail clearly on overflow. |
| Nullable paths | Keep public paths as `string`; reject unexpected `NULL` paths with `EINVAL` | The first FUSE 3 API does not expose `string option` paths. Do not enable or support `nullpath_ok` behavior in M3. |
| Rename flags | Expose decoded plus raw flags in `Fuse`; reject nonzero raw flags in compat | The new API can represent FUSE 3 behavior. The old API cannot. |
| Readdir entries | Expose `dir_entry list` in `Fuse`; keep `string list` in compat | This preserves the old simple path while allowing `FUSE_FILL_DIR_PLUS` and offsets in the new API. |
| Timestamp sentinels | Expose `Now` and `Omit` in `Fuse`; compat uses concrete `Time` values | FUSE 3 can pass sentinel values that old `utime` floats cannot represent. |
| `init` | Keep `unit -> unit` in M3 | The current binding does not expose connection or config data, and this can be added later without blocking parity. |
| xattr flags | Keep the existing `xattr_flags` type | FUSE 3 does not require a public API change for the currently implemented xattr callbacks. |
| Examples and e2e | Defer full updates to M4 | M3 should keep the library build green and prove compatibility shape, but M4 owns user-facing example and mounted behavior updates. |

## Compatibility Module Shape

Expose the compatibility API as:

```ocaml
module Fuse_compat : sig
  type operations = {
    getattr : string -> Unix.LargeFile.stats;
    readlink : string -> string;
    mknod : string -> int -> unit;
    mkdir : string -> int -> unit;
    unlink : string -> unit;
    rmdir : string -> unit;
    symlink : string -> string -> unit;
    rename : string -> string -> unit;
    link : string -> string -> unit;
    chmod : string -> int -> unit;
    chown : string -> int -> int -> unit;
    truncate : string -> int64 -> unit;
    utime : string -> float -> float -> unit;
    fopen : string -> Unix.open_flag list -> int option;
    read : string -> buffer -> int64 -> int -> int;
    write : string -> buffer -> int64 -> int -> int;
    statfs : string -> Unix_util.statvfs;
    flush : string -> int -> unit;
    release : string -> Unix.open_flag list -> int -> unit;
    fsync : string -> bool -> int -> unit;
    setxattr : string -> string -> string -> xattr_flags -> unit;
    getxattr : string -> string -> string;
    listxattr : string -> string list;
    removexattr : string -> string -> unit;
    opendir : string -> Unix.open_flag list -> int option;
    readdir : string -> int -> string list;
    releasedir : string -> Unix.open_flag list -> int -> unit;
    fsyncdir : string -> bool -> int -> unit;
    init : unit -> unit;
  }

  val default_operations : operations
  val main : Fuse_bindings.str array -> operations -> unit
end
```

This is the old API shape. The main `Fuse.operations` record should be the
FUSE-3-shaped record from `public-api-proposal.md`.

## Verification

Run these checks for M3:

```sh
tools/format_ocaml lib/Fuse.ml lib/Fuse.mli lib/Fuse_lib.ml
tools/format_c lib/Fuse_util.c
dune build @install
```

Also check that the old temporary M2 callback API no longer appears in the main
API:

```sh
rg -n "utime :|mlname\\(utime\\)|temporary|struct utimbuf|fuse_read_cmd|fuse_process_cmd" lib
```

Expected result: remaining `utime` references are inside `Fuse.Fuse_compat` or
historical planning docs only.

If a small compatibility compile check is added, it should build through
`Fuse.Fuse_compat.main` without requiring `/dev/fuse`.
