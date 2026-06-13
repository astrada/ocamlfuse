# M0 Checks: Decisions And Environment

Status: complete.

Checked on 2026-06-13.

## Decision Checklist

| Requirement | Decision |
| --- | --- |
| FUSE version support | libfuse 3 only |
| Minimum libfuse version | `3.10`, for Ubuntu Jammy support |
| FUSE API level | `FUSE_USE_VERSION 30` |
| Dune/opam package name | `ocamlfuse3` |
| Conf package name | `conf-libfuse3` |
| Main OCaml module | `Fuse` |
| Compatibility module | `Fuse_compat` |
| Public API shape | FUSE-3-shaped `Fuse`, old API via `Fuse_compat` |
| Initial callback scope | Only callbacks needed to replace current behavior |

## Environment Checks

`pkg-config --modversion fuse3` reports:

```text
3.14.0
```

`pkg-config --cflags --libs fuse3` reports:

```text
-I/usr/include/fuse3 -lfuse3 -lpthread
```

`/usr/include/fuse3` exists and contains the expected libfuse 3 headers:

```text
cuse_lowlevel.h
fuse.h
fuse_common.h
fuse_log.h
fuse_lowlevel.h
fuse_opt.h
libfuse_config.h
```

## Header Sanity Check

A compile-only C sanity check succeeded with:

- `FUSE_USE_VERSION 30`
- `#include <fuse.h>`
- FUSE 3 callback signatures for `getattr`, `rename`, `readdir`, and `init`
- assignment into `struct fuse_operations`
- linking with `-lfuse3 -lpthread`

This confirms that the chosen FUSE API level is accepted by the local libfuse
`3.14.0` headers while staying within the planned Ubuntu Jammy compatibility
target.
