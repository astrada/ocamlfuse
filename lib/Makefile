OCAMLMAKEFILE=../OCamlMakefile

SOURCES=Result.ml Thread_pool.ml Unix_util.ml Unix_util_stubs.c Fuse_bindings.idl Fuse_util.c Fuse_lib.ml Fuse.ml
RESULT=Fuse
LIBS=bigarray
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
	CLIBS=osxfuse
	CPPFLAGS=-I/usr/local/include/osxfuse
	INCDIRS=$(shell opam config var lib)/camlidl
	LIBDIRS=/usr/local/lib
else
	CLIBS=fuse
endif
OCAMLLDFLAGS=-linkall
THREADS=threads
TRASH=*~ \\\#*
CFLAGS+=-D_FILE_OFFSET_BITS=64 -I. -pthread

LIBINSTALL_FILES=Fuse.a Fuse.cma Fuse.cmi Fuse.mli Fuse.cmxa Fuse_bindings.cmi Fuse_lib.cmi Unix_util.cmi dllFuse_stubs.so libFuse_stubs.a
ifndef OCAML_LIB_INSTALL
	OCAML_LIB_INSTALL=$(OCAMLLIBPATH)/site-packages/ocamlfuse
endif

all: native-code-library byte-code-library

install: libinstall
uninstall: libuninstall

-include $(OCAMLMAKEFILE)
