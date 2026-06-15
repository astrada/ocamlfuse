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
 (name conf-libfuse3)
 (synopsis "Virtual package relying on FUSE 3")
 (description "This package can only install if the fuse3 library is installed on the system.")
 (maintainers "https://github.com/ocaml/opam-repository/issues")
 (authors "Multiple")
 (homepage "https://github.com/libfuse/libfuse")
 (bug_reports "https://github.com/ocaml/opam-repository/issues")
 (license "LGPL-2.1-only")
 (allow_empty)
 (depends
  ("conf-pkg-config" :build)))

(package
 (name ocamlfuse3)
 (synopsis "OCaml bindings for FUSE 3 (Filesystem in UserSpacE)")
 (description "\
This is a binding to FUSE 3 for the OCaml programming language, enabling
users to implement high-level FUSE filesystems in OCaml. It has been designed
with simplicity as a goal, as you can see by looking at example/fusexmp.ml.
The Bigarray library is used for read and write buffers, allowing the library
to do zero-copy in OCaml land.")
 (depends
  (ocaml (>= 4.08.0))
  base-bigarray
  base-threads
  base-unix
  camlidl
  dune-configurator
  conf-libfuse3
  ("ounit2" :with-test)))
