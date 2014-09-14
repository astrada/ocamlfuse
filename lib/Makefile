OCAMLMAKEFILE=../OCamlMakefile

SOURCES=Result.ml Unix_util.ml Unix_util_stubs.c Fuse_bindings.idl Fuse_util.c Fuse_lib.ml Fuse.ml
RESULT=Fuse
LIBS=bigarray
CLIBS=fuse
OCAMLLDFLAGS=-linkall
THREADS=threads
TRASH=*~ \\\#*
CFLAGS+=-D_FILE_OFFSET_BITS=64 -I. -pthread

LIBINSTALL_FILES=Fuse.a Fuse.cma Fuse.cmi Fuse.mli Fuse.cmxa Fuse_bindings.cmi Fuse_lib.cmi Unix_util.cmi dllFuse_stubs.so libFuse_stubs.a
ifeq ($(OS),Windows_NT)
#OS is windows
$(error Sorry, ocamlfuse doesn't work on Windows.)
else
    UNAME_S := $(shell uname -s)
    ifeq ($(UNAME_S),Darwin)
        CPPFLAGS += -DFUSE_USE_VERSION=26 -I/usr/local/include/osxfuse 
    endif
endif

ifndef OCAML_LIB_INSTALL
	OCAML_LIB_INSTALL=$(OCAMLLIBPATH)/site-packages/ocamlfuse
endif

all: native-code-library byte-code-library

install: libinstall
uninstall: libuninstall

-include $(OCAMLMAKEFILE)
