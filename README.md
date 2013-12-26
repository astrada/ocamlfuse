ocamlfuse
=========

This repository is cloned from the last CVS snapshot of
[OCamlFuse](http://sourceforge.net/projects/ocamlfuse/), with OASIS support
added. And with a [patch](https://github.com/astrada/ocamlfuse/pull/1) from
Sorin Ionescu to fix an issue with osxfuse (Mac OS X).

Last updated: 2013-12-26

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

