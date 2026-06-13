# M4 Plan: Native Examples And e2e Tests

Status: complete; M4-specific decisions are closed in this plan.

Depends on M3, which is complete.

## Goal

Move the executable examples and mounted e2e test filesystem from
`Fuse.Fuse_compat` to the native FUSE-3-shaped `Fuse` API, then validate the
implemented callbacks with the smoke and full e2e suites.

M4 should prove that real users can implement filesystems with the new public
API. The old compatibility API should remain compile-covered, but it should no
longer be the path used by examples or the mounted e2e filesystem.

## Non-Goals

- Do not change the public API shape unless M4 uncovers a concrete bug in the
  M3 API.
- Do not add optional FUSE 3 callbacks that are still outside the first callback
  parity scope.
- Do not add multithreaded loop behavior; M6 owns that analysis.
- Do not require kernel-dependent `FUSE_READDIR_PLUS` behavior for the e2e
  suite.
- Do not commit generated camlidl files.

## Starting Point

At the end of M3, the binding exposed the FUSE-3-shaped `Fuse.operations`
record and the nested `Fuse.Fuse_compat` module. The examples and
`test/e2e/testfs.ml` opened `Fuse.Fuse_compat` to keep the old operation
records compiling.

M4 removed those compatibility opens from executable examples and mounted e2e
code, updated callback implementations to native FUSE 3 shapes, and kept a
small compile-only compatibility target so the upgrade path remains checked.

## Implementation Results

- `example/hello.ml` and `example/fusexmp.ml` use native `Fuse`.
- `test/e2e/testfs.ml` uses native `Fuse` and the FUSE 3 callback shapes.
- `test/e2e/client.ml` contains full-suite assertions for `utimens`
  `UTIME_NOW`/`UTIME_OMIT` behavior and `RENAME_NOREPLACE`.
- `test/e2e/xattr_stubs.c` provides the Linux helpers used by those assertions.
- `test/e2e/compat_compile.ml` is the only compatibility-module check.
- `test/e2e/run.sh` builds the test filesystem, client, and compatibility
  compile target before running mounted tests.

## Implementation Checklist

1. Update `example/hello.ml` to use native `Fuse`:
   - remove `open Fuse.Fuse_compat`;
   - change `getattr` to accept `file_info option`;
   - change `fopen` to accept `file_info` and return
     `default_file_info_update`;
   - change `read` to accept `file_info`;
   - change `readdir` to accept offset, file info, and request flags, and
     return `dir_entry list`.
2. Update `example/fusexmp.ml` to use native `Fuse`:
   - remove `open Fuse.Fuse_compat`;
   - store file descriptors as `file_handle` values with checked conversions;
   - return `file_info_update` from `fopen` and `opendir`;
   - read file handles from `file_info.fi_fh` in read/write/flush/release/fsync
     callbacks;
   - implement native `utimens`;
   - return `dir_entry list` from `readdir`.
3. Update `test/e2e/testfs.ml` to use native `Fuse`:
   - remove `open Fuse.Fuse_compat`;
   - convert file descriptors to and from `file_handle` with checked helpers;
   - update callbacks that receive `file_info option`;
   - update file and directory callbacks to consume `file_info`;
   - return `file_info_update` from `fopen` and `opendir`;
   - log `utimens` instead of `utime`;
   - return `dir_entry list` from `readdir`;
   - support concrete `Time`, `Now`, and `Omit` timestamps in `utimens`;
   - implement normal rename and `RENAME_NOREPLACE`; reject unsupported rename
     flags with `EINVAL`.
4. Update `test/e2e/client.ml`:
   - expect the `utimens` event instead of `utime`;
   - add a full-suite test for `UTIME_NOW`/`UTIME_OMIT` through a Linux C stub;
   - add a full-suite test for `RENAME_NOREPLACE` through a Linux C stub;
   - keep the smoke suite focused on fast create/read/write/unlink behavior.
5. Extend `test/e2e/xattr_stubs.c` rather than adding another C stub file:
   - add a `utimens_now_omit` helper using `utimensat`;
   - add a `rename_noreplace` helper using `renameat2` or the corresponding
     Linux syscall;
   - return normal `Unix.Unix_error` values through the existing stub style.
6. Add a compile-only compatibility target:
   - create a small source that constructs a `Fuse.Fuse_compat.operations`
     value and references `Fuse.Fuse_compat.main`;
   - build it from `test/e2e/run.sh`;
   - do not mount or execute it.
7. Update `test/e2e/dune` and `test/e2e/run.sh`:
   - build the native test filesystem and client;
   - build the compile-only compatibility target;
   - preserve current skip behavior when FUSE is unavailable.
8. Format touched OCaml and C files.
9. Update planning docs with implementation results after M4 is complete.

## M4-Specific Decisions

| Topic | Decision | Reason |
| --- | --- | --- |
| Examples API | Use native `Fuse`, not `Fuse.Fuse_compat` | Examples should demonstrate the new public API after M4. |
| e2e filesystem API | Use native `Fuse`, not `Fuse.Fuse_compat` | The mounted acceptance test should exercise the production FUSE 3 surface. |
| Compatibility coverage | Add a compile-only compatibility target | After examples/e2e migrate away from compat, this keeps the old API shape checked without mounting a second filesystem. |
| File handles | Store descriptors as `file_handle` with checked int conversions | The native API uses `int64`; Unix file descriptors still need `int` for `Unix_util.file_descr_of_int`. |
| `file_info` assertions | Use `file_info.fi_fh` for behavior, but do not assert exact raw flags | Kernel and mount options can affect flags. Handle use gives practical conversion coverage without brittle checks. |
| `utimens` | Implement `Time`, `Now`, and `Omit` in the native test filesystem | The public API exposes timestamp sentinels, so M4 should validate that they can drive real behavior. |
| Rename flags | Implement and test `RENAME_NOREPLACE`; reject exchange, whiteout, and unknown flags with `EINVAL` | This exercises FUSE 3 rename flag decoding while avoiding more complex semantics that are not needed for callback parity. |
| `readdir` entries | Return names with no stats, no offsets, and default fill flags | This matches existing stateless behavior while using the native `dir_entry` type. |
| `FUSE_READDIR_PLUS` | Do not require a deterministic e2e assertion | Whether the kernel asks for plus entries is mount/kernel-policy dependent. |
| Smoke vs full suite | Keep FUSE-3-specific rename and timestamp tests in the full suite | The smoke test should remain fast and focused on basic mounted I/O. |
| Verification environment | Run mounted tests outside the sandbox | `/dev/fuse` access is not available inside the sandbox. |

## Compatibility Target Shape

The compile-only target should be intentionally small:

```ocaml
open Fuse.Fuse_compat

let _ops : operations =
  {
    default_operations with
    init = (fun () -> ());
    getattr = Unix.LargeFile.lstat;
  }

let _main = main
```

This checks that the nested compatibility module remains usable without
starting a FUSE filesystem.

## Verification

These checks passed for M4:

```sh
tools/format_ocaml \
  example/hello.ml example/fusexmp.ml \
  test/e2e/testfs.ml test/e2e/client.ml test/e2e/compat_compile.ml
tools/format_c test/e2e/xattr_stubs.c
dune build @install
dune build example/hello.exe example/fusexmp.exe
dune build test/e2e/testfs.exe test/e2e/client.exe test/e2e/compat_compile.exe
make test
make e2e
OCAMLFUSE_E2E_REQUIRE_FUSE=1 make test
git diff --check
```

Mounted test commands were run outside the sandbox on a Linux host with
`/dev/fuse` access:

- `make test`: passed, running the smoke suite.
- `make e2e`: passed, running the full 9-test suite.
- `OCAMLFUSE_E2E_REQUIRE_FUSE=1 make test`: passed, proving the required-FUSE
  smoke path works.

The sandbox skip path was checked separately with `make test` inside the
sandbox, where `/dev/fuse` is unavailable. It printed `SKIP` and exited
successfully.

Also check that examples and the mounted test filesystem no longer use the
compatibility module:

```sh
rg -n "Fuse_compat|open Fuse\\.Fuse_compat" \
  example test/e2e/testfs.ml test/e2e/compat_compile.ml
```

Result: only `test/e2e/compat_compile.ml` references `Fuse.Fuse_compat`.
