(lang dune 3.7)

(generate_opam_files true)

(source (github astrada/ocamlfuse))
(authors
 "Vincenzo Ciancia"
 "Olaf Hering <olaf@aepfle.de>"
 "Alessandro Strada <alessandro.strada@gmail.com>")
(maintainers "Alessandro Strada <alessandro.strada@gmail.com>")
(license "GPL-1.0-or-later")

(package
 (name conf-libfuse)
 (synopsis "Virtual package relying on FUSE")
 (description "This package can only install if the fuse library is installed on the system.")
 (maintainers "https://github.com/ocaml/opam-repository/issues")
 (authors "Multiple")
 (homepage "https://github.com/libfuse/libfuse")
 (bug_reports "https://github.com/ocaml/opam-repository/issues")
 (license "LGPL-2.1-only")
 (allow_empty)
 (depends
  ("conf-pkg-config" :build)))

(package
 (name ocamlfuse)
 (synopsis "OCaml bindings for FUSE (Filesystem in UserSpacE)")
 (description "\
This is a binding to FUSE for the OCaml programming language, enabling
you to write multithreaded filesystems in the OCaml language. It has
been designed with simplicity as a goal, as you can see by looking at
example/fusexmp.ml. Efficiency has also been a separate goal. The
Bigarray library is used for read and writes, allowing the library to
do zero-copy in OCaml land.")
 (depends
  (ocaml (>= 4.02.3))
  base-bigarray
  base-threads
  base-unix
  camlidl
  dune-configurator
  conf-libfuse))
