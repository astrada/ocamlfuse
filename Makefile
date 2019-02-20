
build:
	@dune build @install

install: build
	@dune install

uninstall: build
	@dune uninstall

clean:
	@dune clean

example:
	@dune build example/hello.exe
	@dune build example/fusexmp.exe

.PHONY: build install uninstall clean example

