#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/unixsupport.h>

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#if defined(__linux__)
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/xattr.h>
#include <unistd.h>
#endif

#ifndef RENAME_NOREPLACE
#define RENAME_NOREPLACE (1 << 0)
#endif

static void fail_errno(const char *function_name, value pathv) {
  uerror(function_name, pathv);
}

#if defined(__linux__)

CAMLprim value ocamlfuse_e2e_setxattr(value pathv, value namev, value valuev) {
  CAMLparam3(pathv, namev, valuev);
  int result = setxattr(String_val(pathv), String_val(namev),
                        String_val(valuev), caml_string_length(valuev), 0);
  if (result == -1)
    fail_errno("setxattr", pathv);
  CAMLreturn(Val_unit);
}

CAMLprim value ocamlfuse_e2e_getxattr(value pathv, value namev) {
  CAMLparam2(pathv, namev);
  CAMLlocal1(result);
  ssize_t length = getxattr(String_val(pathv), String_val(namev), NULL, 0);
  if (length == -1)
    fail_errno("getxattr", pathv);

  result = caml_alloc_string(length);
  if (length > 0) {
    ssize_t read_length = getxattr(String_val(pathv), String_val(namev),
                                   (char *)String_val(result), length);
    if (read_length == -1)
      fail_errno("getxattr", pathv);
  }

  CAMLreturn(result);
}

CAMLprim value ocamlfuse_e2e_listxattr(value pathv) {
  CAMLparam1(pathv);
  CAMLlocal3(result, name, cons);
  ssize_t length = listxattr(String_val(pathv), NULL, 0);
  if (length == -1)
    fail_errno("listxattr", pathv);
  if (length == 0)
    CAMLreturn(Val_int(0));

  char *buffer = malloc(length);
  if (buffer == NULL)
    caml_failwith("listxattr: could not allocate buffer");

  ssize_t read_length = listxattr(String_val(pathv), buffer, length);
  if (read_length == -1) {
    free(buffer);
    fail_errno("listxattr", pathv);
  }

  result = Val_int(0);
  char *cursor = buffer;
  char *end = buffer + read_length;
  while (cursor < end) {
    name = caml_copy_string(cursor);
    cons = caml_alloc(2, 0);
    Store_field(cons, 0, name);
    Store_field(cons, 1, result);
    result = cons;
    cursor += strlen(cursor) + 1;
  }

  free(buffer);
  CAMLreturn(result);
}

CAMLprim value ocamlfuse_e2e_removexattr(value pathv, value namev) {
  CAMLparam2(pathv, namev);
  int result = removexattr(String_val(pathv), String_val(namev));
  if (result == -1)
    fail_errno("removexattr", pathv);
  CAMLreturn(Val_unit);
}

CAMLprim value ocamlfuse_e2e_utimens_now_omit(value pathv) {
  CAMLparam1(pathv);
  struct timespec times[2];
  times[0].tv_sec = 0;
  times[0].tv_nsec = UTIME_NOW;
  times[1].tv_sec = 0;
  times[1].tv_nsec = UTIME_OMIT;
  if (utimensat(AT_FDCWD, String_val(pathv), times, 0) == -1)
    fail_errno("utimensat", pathv);
  CAMLreturn(Val_unit);
}

CAMLprim value ocamlfuse_e2e_rename_noreplace(value oldpathv, value newpathv) {
  CAMLparam2(oldpathv, newpathv);
#if defined(SYS_renameat2)
  long result = syscall(SYS_renameat2, AT_FDCWD, String_val(oldpathv), AT_FDCWD,
                        String_val(newpathv), RENAME_NOREPLACE);
#else
  errno = ENOSYS;
  long result = -1;
#endif
  if (result == -1)
    fail_errno("renameat2", oldpathv);
  CAMLreturn(Val_unit);
}

#else

CAMLprim value ocamlfuse_e2e_setxattr(value pathv, value namev, value valuev) {
  CAMLparam3(pathv, namev, valuev);
  caml_failwith("Linux xattr API is required");
  CAMLreturn(Val_unit);
}

CAMLprim value ocamlfuse_e2e_getxattr(value pathv, value namev) {
  CAMLparam2(pathv, namev);
  caml_failwith("Linux xattr API is required");
  CAMLreturn(Val_int(0));
}

CAMLprim value ocamlfuse_e2e_listxattr(value pathv) {
  CAMLparam1(pathv);
  caml_failwith("Linux xattr API is required");
  CAMLreturn(Val_int(0));
}

CAMLprim value ocamlfuse_e2e_removexattr(value pathv, value namev) {
  CAMLparam2(pathv, namev);
  caml_failwith("Linux xattr API is required");
  CAMLreturn(Val_unit);
}

CAMLprim value ocamlfuse_e2e_utimens_now_omit(value pathv) {
  CAMLparam1(pathv);
  caml_failwith("Linux utimensat API is required");
  CAMLreturn(Val_unit);
}

CAMLprim value ocamlfuse_e2e_rename_noreplace(value oldpathv, value newpathv) {
  CAMLparam2(oldpathv, newpathv);
  caml_failwith("Linux renameat2 API is required");
  CAMLreturn(Val_unit);
}

#endif
