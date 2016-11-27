ocamlfuse
=========

This repository is cloned from the last CVS snapshot of
[OCamlFuse](http://sourceforge.net/projects/ocamlfuse/), with:
* OASIS support added.
* Patches (see [#1](https://github.com/astrada/ocamlfuse/pull/1) and [#3](https://github.com/astrada/ocamlfuse/pull/3)) to make it compile on Mac OS X. 
* Fix for a race condition in multi-threaded mode (see [#4](https://github.com/astrada/ocamlfuse/issue/4)).

Last updated: 2016-11-27

### Requirements

 * camlidl

### Build and install

To build the library:

    $ ocaml setup.ml -configure
    $ ocaml setup.ml -build

To install:

    $ ocaml setup.ml -install

To uninstall:

    $ ocaml setup.ml -uninstall

