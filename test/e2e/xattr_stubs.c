#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__linux__)
#include <sys/types.h>
#include <sys/xattr.h>
#endif

static void fail_errno(const char *function_name) {
  char message[256];
  snprintf(message, sizeof(message), "%s: %s", function_name, strerror(errno));
  caml_failwith(message);
}

#if defined(__linux__)

CAMLprim value ocamlfuse_e2e_setxattr(value pathv, value namev, value valuev) {
  CAMLparam3(pathv, namev, valuev);
  int result =
      setxattr(String_val(pathv), String_val(namev), String_val(valuev),
               caml_string_length(valuev), 0);
  if (result == -1)
    fail_errno("setxattr");
  CAMLreturn(Val_unit);
}

CAMLprim value ocamlfuse_e2e_getxattr(value pathv, value namev) {
  CAMLparam2(pathv, namev);
  CAMLlocal1(result);
  ssize_t length = getxattr(String_val(pathv), String_val(namev), NULL, 0);
  if (length == -1)
    fail_errno("getxattr");

  result = caml_alloc_string(length);
  if (length > 0) {
    ssize_t read_length =
        getxattr(String_val(pathv), String_val(namev), (char *)String_val(result),
                 length);
    if (read_length == -1)
      fail_errno("getxattr");
  }

  CAMLreturn(result);
}

CAMLprim value ocamlfuse_e2e_listxattr(value pathv) {
  CAMLparam1(pathv);
  CAMLlocal3(result, name, cons);
  ssize_t length = listxattr(String_val(pathv), NULL, 0);
  if (length == -1)
    fail_errno("listxattr");
  if (length == 0)
    CAMLreturn(Val_int(0));

  char *buffer = malloc(length);
  if (buffer == NULL)
    caml_failwith("listxattr: could not allocate buffer");

  ssize_t read_length = listxattr(String_val(pathv), buffer, length);
  if (read_length == -1) {
    free(buffer);
    fail_errno("listxattr");
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
    fail_errno("removexattr");
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

#endif
