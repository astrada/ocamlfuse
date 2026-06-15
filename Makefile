
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

test:
	@dune runtest

e2e-smoke-test:
	@dune build @install
	@test/e2e/run.sh smoke

e2e-multithreaded-smoke-test:
	@dune build @install
	@OCAMLFUSE_E2E_LOOP_MODE=multi test/e2e/run.sh smoke

e2e:
	@dune build @install
	@test/e2e/run.sh full

format:
	tools/format_ocaml $(FILES)

format-c:
	tools/format_c $(FILES)

.PHONY: build install uninstall clean example test e2e-smoke-test e2e-multithreaded-smoke-test e2e format format-c
