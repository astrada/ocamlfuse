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

  Warning: this main() contains a hack that's requested for compatibility
  with OCaml version 5 and later. The new Multicore runtime prohibits
  calling a fork() from C after caml_main() is called. So, I'm calling
  fuse_daemonize() before caml_main(), and I try to detect any option that
  keeps the process in foreground. But there are a couple of problems with this
  hack: First, if the foreground option is injected by caml_main(), I will miss
  it. Also, fuse_daemonize() redirects stdout and stderr to /dev/null, so it
  gobbles up any error message produced by caml_main().

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
void start_program(int argc, char **argv, char *mountpoint, int foreground);
void parse_fuse_args(int argc, char **argv, struct fuse_args *args,
                     bool *debug);
bool is_fuse_arg(char *arg, char *prev, bool is_last);
bool is_debug(char *arg);
int main_ocaml5(int argc, char **argv);
int main_ocaml4(int argc, char **argv);

/* https://v2.ocaml.org/releases/5.1/htmlman/intfc.html#ss:main-c */
int main(int argc, char **argv) {
#if OCAML_VERSION < 50000
  main_ocaml4(argc, argv);
#else
  main_ocaml5(argc, argv);
#endif
}

/* https://v2.ocaml.org/releases/5.1/htmlman/intfc.html#ss:main-c */
int main_ocaml5(int argc, char **argv) {
  struct fuse_args args = FUSE_ARGS_INIT(0, NULL);
  char *mountpoint;
  int foreground;
  bool debug;

  parse_fuse_args(argc, argv, &args, &debug);
  if (fuse_parse_cmdline(&args, &mountpoint, NULL, &foreground) != -1) {
    if (debug) {
      foreground = 1;
    }
    start_program(argc, argv, mountpoint, foreground);

    fuse_opt_free_args(&args);
    return 0;
  }

  fuse_opt_free_args(&args);
  return 1;
}

int main_ocaml4(int argc, char **argv) { caml_main(argv); }

void parse_fuse_args(int argc, char **argv, struct fuse_args *args,
                     bool *debug) {
  int i = 1;

  fuse_opt_add_arg(args, argv[0]);
  while (i < argc) {
    if (is_fuse_arg(argv[i], argv[i - 1], i == argc - 1)) {
      fuse_opt_add_arg(args, argv[i]);
    }
    if (is_debug(argv[i])) {
      *debug = true;
    }
    ++i;
  }
}

bool is_fuse_arg(char *arg, char *prev, bool is_last) {
  if (strcmp(arg, "--help") == 0) {
    return true;
  }
  if (strcmp(arg, "--version") == 0) {
    return true;
  }
  if (arg[0] == '-') {
    switch (arg[1]) {
    case 'o':
    case 'h':
    case 'V':
    case 'd':
    case 'f':
    case 's':
      return true;
    }
  } else {
    if (prev != NULL && strcmp(prev, "-o") == 0) {
      return true;
    } else {
      if (is_last && access(arg, F_OK) == 0) {
        return true;
      }
    }
  }
  return false;
}

bool is_debug(char *arg) {
  if (strcmp(arg, "--debug") == 0) {
    return true;
  }
  if (strcmp(arg, "-debug") == 0) {
    return true;
  }
  return false;
}

void start_program(int argc, char **argv, char *mountpoint, int foreground) {
  char **fuse_argv = argv;

  if (mountpoint != NULL) {
    /* https://github.com/libfuse/libfuse/blob/fuse-2.9.9/include/fuse_common.h#L246
     */
    if (fuse_daemonize(foreground) == -1) {
      perror("fuse_daemonize");
      exit(1);
    }

    if (!foreground) {
      fuse_argv = insert_foreground_option(argc, argv);
    }
  }

  caml_main(fuse_argv);

  if (fuse_argv != argv) {
    free_fuse_argv(argc + 1, fuse_argv);
  }
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
