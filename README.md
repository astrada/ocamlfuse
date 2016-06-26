ocamlfuse
=========

This repository is cloned from the last CVS snapshot of
[OCamlFuse](http://sourceforge.net/projects/ocamlfuse/), with OASIS support
added, and with patches (see #1 and #3) to make it compile on Mac OS X. 

Last updated: 2016-06-26

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

