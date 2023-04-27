ocamlfuse
=========

This repository is cloned from the last CVS snapshot of
[OCamlFuse](https://sourceforge.net/projects/ocamlfuse/), with:
* Patches (see [#1](https://github.com/astrada/ocamlfuse/pull/1) and [#3](https://github.com/astrada/ocamlfuse/pull/3)) to make it compile on Mac OS X.
* Fix for a race condition in multi-threaded mode (see [#4](https://github.com/astrada/ocamlfuse/issue/4)).
* [dune](https://github.com/ocaml/dune) support (see [#12](https://github.com/astrada/ocamlfuse/pull/12)).
* See all the merged [PR](https://github.com/astrada/ocamlfuse/pulls?q=is%3Apr+is%3Aclosed)

INTRODUCTION

This is a binding to `fuse` for the OCaml programming language, enabling
you to write multithreaded filesystems with the OCaml language. It has
been designed with simplicity as a goal, as you can see by looking at
`example/fusexmp.ml`. Efficiency has also been a separate goal. The
`Bigarray` library is used for read and writes, allowing the library to
do zero-copy in OCaml land.

REQUIREMENTS

You need `fuse` (version 2.7 or greater)

https://www.sourceforge.net/projects/fuse

You also need `OCaml >= 4.02.3` and `camlidl >= 1.05`.

GETTING STARTED

The recommended way to install this library is with
[opam](https://opam.ocaml.org/).

    opam install ocamlfuse


INSTALLATION

If you don't want to install `opam`, you need to manually install this
prerequisites:

1) Prerequisites

- Fuse

  Should be in the major linux distributions, but you can find it at

  https://fuse.sourceforge.net

  You need to install `libfuse-dev` in debian and ubuntu.

- OCaml >= 4.02.3

  Should be in the major linux distributions, but is also available at

  https://ocaml.org

- CamlIDL >= 1.05

  present at least in ubuntu, also available at

  https://github.com/xavierleroy/camlidl

- dune >= 3.7

  available at

  https://dune.build/

2) Installing OCamlFuse

  unpack the tarball, then

    make
    make install

  This will install ocamlfuse in your ocaml library directory. To uninstall
  it you can run `make uninstall`.

TESTING

    make example
    cd _build/default/example
    mkdir tmp
    ./fusexmp.exe tmp
    cd tmp #you'll find a copy of your "/" directory here

NOTE: if you access the "clone" of the mountpoint of the filesystem, the fs will hang (kill it and then use fusermount -u to umount it). This is a known bug/limitation.

BEFORE YOU WRITE YOUR OWN FILESYSTEM

KNOWN PROBLEMS (if you can help, please do)

- The stateful interface for readdir is not implemented

- There is a stub in `Fuse_util.c` regarding `st_blocks` - if one
  implements statfs with a block size different
  than 512 "du" will not work on the filesystem.

- many ocaml exceptions are reported as 127

- we should add non-blocking `lstat64` and `statfs`, `*xattr` implementations
  for ocaml in `Unix_util`

- translation between ocaml unix errors and C unix error is dependent
  on the order of constructor names in ocaml. There should be a way to
  get error names from caml and create a translation table.

- the `Unix_util` library uses unsafe coercions between unix file
  handles (which are defined as ints) and ints. Even if this works, in
  the future it might stop working.

- IMPORTANT: `Unix_util.read` and `write` operations have not been tested
  in case of errors. Error code conversion might be incorrect but I
  don't have test cases (maybe the easy way is to modify fusexmp to
  return various errors).

- Unix errors which are unknown to ocaml should be reported as EUNKNOWNERR

- Test statfs (never used until now)

- Some errors are missing in the unix module (e.g. ENOTSUP,ENOATTR,
  see man lsxattr). We could solve all these problems with errors using
  a custom error type instead of `unix_error` but this would create
  troubles.

- deadlock (and consequent necessity to kill -KILL the program) if
  accessing the mountpoint mirrored inside the mountpoint in
  fusexmp. I remember it was easy to understand why, but right now I
  have no idea.

HELPING THE PROJECT

The best help you can give to the project is to test everything,
including, but not limited to:

- large file operations (files >= 4gb)

- multithreaded operations: the filesystem should always be responsive,
  no matter if reading a certain file blocks

- robustness: the filesystem should NEVER exit from its mainloop if not
  explicitly requested from the user.

Please report if you do serious tests! We need to know which programs
did you use, if you found any bug, and how to reproduce the tests.

Also, we need packaging, I don't have the necessary time and don't know
ocamlfindlib or GODI. Please if you have the time and the necessary
knowledge help with packaging. Autoconf support would be highly appreciated,
too.

 A mailing list has been set up on sourceforge, you are strongly
encouraged to post feedback there and in general to subscribe if you use ocamlfuse.

The sourceforge page for ocamlfuse is

https://sourceforge.net/projects/ocamlfuse

Bye and have fun

Vincenzo Ciancia

vincenzo_ml at yahoo dot it
ciancia at di dot unipi dot it
applejack at users dot sourceforge dot net
