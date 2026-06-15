# fuse3

`fuse3` provides OCaml bindings for libfuse 3. It lets OCaml programs
implement high-level FUSE filesystems while using Bigarray-backed buffers for
read and write callbacks.

The public Dune and opam package is `fuse3`. The OCaml module remains
`Fuse`.

## Requirements

- Linux
- libfuse `>= 3.10`
- `pkg-config`
- OCaml `>= 4.08.0`
- camlidl
- Dune `>= 3.7`

On Debian and Ubuntu, install the FUSE development package with:

```sh
sudo apt install libfuse3-dev
```

## Installation

The recommended installation path is opam:

```sh
opam install fuse3
```

For local development:

```sh
make
make install
```

To uninstall a local installation:

```sh
make uninstall
```

## Building And Testing

Build the library and install metadata:

```sh
make
```

Build the examples:

```sh
make example
```

Run the unit and compile checks:

```sh
make test
```

Run the mounted smoke test:

```sh
make e2e-smoke-test
```

Run the full mounted end-to-end suite:

```sh
make e2e
```

Run the full mounted end-to-end suite in multithreaded mode:

```sh
make e2e-multithreaded
```

The mounted tests require Linux, `/dev/fuse` access, and permission to mount
FUSE filesystems. When FUSE access is unavailable, `make e2e-smoke-test` prints
`SKIP` and exits successfully. Set `OCAMLFUSE_E2E_REQUIRE_FUSE=1` to make
missing FUSE support a failure.

## Examples

The examples are in `example/`:

- `hello.ml`: a minimal read-only filesystem.
- `fusexmp.ml`: a passthrough-style filesystem.

After `make example`, the executables are under `_build/default/example/`.

Example:

```sh
mkdir -p /tmp/fuse3-mnt
_build/default/example/hello.exe /tmp/fuse3-mnt -f -s
```

Unmount the filesystem from another shell when finished:

```sh
fusermount3 -u /tmp/fuse3-mnt
```

Some systems still provide the unmount command as `fusermount`.

## API Notes

New code should use the native `Fuse` API. The native operation record exposes
FUSE 3 concepts such as:

- `file_info` values on callbacks that receive FUSE file information;
- `file_info_update` results from `fopen` and `opendir`;
- `int64` file handles;
- rename flags;
- readdir flags and `dir_entry` values;
- nanosecond `utimens` timestamps, including `Now` and `Omit` sentinels.

`Fuse.Fuse_compat` provides the old operation record shape as an upgrade aid.
It runs on top of the FUSE 3 implementation, but it cannot represent every FUSE
3 feature. In particular, compatibility callbacks ignore new file-info
parameters, reject unsupported rename flags with `EINVAL`, reject timestamp
sentinels that old `utime` callbacks cannot represent, and convert file handles
back to `int` with overflow checks.

The default FUSE loop is single-threaded and foreground-oriented. Users can opt
into libfuse's multithreaded loop with `~loop_mode:Multi_threaded`. In that
mode, libfuse owns worker threads and the binding registers those threads with
the OCaml runtime before invoking OCaml callbacks. FUSE `-s` still forces the
single-threaded path.

## Documentation

- `docs/bindings.md`: binding architecture and maintenance notes.
- `docs/release-notes.md`: unreleased FUSE 3 migration notes.
- `docs/plans/fuse3/`: migration planning and milestone history.

## History

This repository descends from the original OCamlFuse project hosted on
SourceForge. It keeps the original GPL-licensed binding lineage while updating
the build, package metadata, tests, and runtime integration for libfuse 3.

Original project page: <https://sourceforge.net/projects/ocamlfuse/>
