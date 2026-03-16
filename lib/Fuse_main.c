/*
  This file is part of the "OCamlFuse" library.

  OCamlFuse is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation (version 2 of the License).

  OCamlFuse is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with OCamlFuse.  See the file LICENSE.  If you haven't received
  a copy of the GNU General Public License, write to:

  Free Software Foundation, Inc.,
  59 Temple Place, Suite 330, Boston, MA
  02111-1307  USA

  Alessandro Strada

  Breaking change: Since v2.7.2, if compiled with OCaml version 5 or later,
  the FUSE process is always started in foreground mode (the `-f` option is
  always injected). In fact, the new Multicore runtime prohibits calling a
  `fork()` from C after `caml_main()` is called. So, we can't let FUSE call
  `fuse_daemonize()` before `caml_main()`. To avoid flawed heuristics to
  decide when to call `fuse_daemonize()`, and usability problems (option
  parsing goes after `fork`, so we loose diagnostics, if the options are
  wrong), the simplest solution is to always keep the process in foreground.
  If you need to run the process in background, remember to append `&` to the
  command line or run the process in a `systemd` service.

  See
  https://discuss.ocaml.org/t/multicore-and-fork-called-from-c-bindings/13993/2
  for further details.
*/

#include <caml/version.h>

#if OCAML_VERSION < 50000
#define CAML_NAME_SPACE
#endif

#include <caml/callback.h>

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define FUSE_USE_VERSION 26
#include <fuse_lowlevel.h>

char **insert_foreground_option(int argc, char **argv);
void free_fuse_argv(int n, char **fuse_argv);
int main_ocaml5(int argc, char **argv);
int main_ocaml4(int argc, char **argv);

/* https://v2.ocaml.org/releases/5.1/htmlman/intfc.html#ss:main-c */
int main(int argc, char **argv) {
#if OCAML_VERSION < 50000
  return main_ocaml4(argc, argv);
#else
  return main_ocaml5(argc, argv);
#endif
}

int main_ocaml5(int argc, char **argv) {
  char **fuse_argv = insert_foreground_option(argc, argv);

  caml_main(fuse_argv);

  free_fuse_argv(argc + 1, fuse_argv);

  return 0;
}

int main_ocaml4(int argc, char **argv) {
  caml_main(argv);
  return 0;
}

char **insert_foreground_option(int argc, char **argv) {
  char **new_argv = malloc((argc + 2) * sizeof(*new_argv));

  new_argv[0] = strdup(argv[0]);
  new_argv[1] = strdup("-f");
  for (int i = 1; i < argc; ++i) {
    new_argv[i + 1] = strdup(argv[i]);
  }
  new_argv[argc + 1] = NULL;
  return new_argv;
}

void free_fuse_argv(int n, char **fuse_argv) {
  for (int i = 0; i < n; ++i) {
    free(fuse_argv[i]);
  }
  free(fuse_argv);
}
