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
*/

#include <caml/version.h>

#if OCAML_VERSION < 50000
#define CAML_NAME_SPACE
#endif

#include <caml/callback.h>
#include <caml/mlvalues.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define FUSE_USE_VERSION 26
#include <fuse_lowlevel.h>

char **insert_foreground_option(int argc, char **argv);
void free_fuse_argv(int n, char **fuse_argv);

/* https://v2.ocaml.org/releases/5.1/htmlman/intfc.html#ss:main-c */
int main(int argc, char **argv) {
  int c;
  int foreground = 0;
  int res;
  char **fuse_argv = argv;

  opterr = 0;
  while ((c = getopt(argc, argv, "f")) != -1) {
    switch (c) {
    case 'f':
      foreground = 1;
      break;
    default:
      break;
    }
  }

  /* https://github.com/libfuse/libfuse/blob/d04687923194d906fe5ad82dcd546c9807bf15b6/include/fuse_common.h#L246
   */
  if (fuse_daemonize(foreground) == -1) {
    perror("fuse_daemonize");
    return 1;
  }

  if (foreground == 0) {
    fuse_argv = insert_foreground_option(argc, argv);
  }

  caml_main(fuse_argv);

  if (foreground == 0) {
    free_fuse_argv(argc + 1, fuse_argv);
  }

  return 0;
}

char **insert_foreground_option(int argc, char **argv) {
  char *mountpoint = argv[argc - 1];
  char **new_argv = malloc((argc + 2) * sizeof(*new_argv));

  for (int i = 0; i < argc - 1; ++i) {
    new_argv[i] = strdup(argv[i]);
  }
  new_argv[argc - 1] = strdup("-f");
  new_argv[argc] = strdup(mountpoint);
  return new_argv;
}

void free_fuse_argv(int n, char **fuse_argv) {
  for (int i = 0; i < n; ++i) {
    free(fuse_argv[i]);
  }
  free(fuse_argv);
}
