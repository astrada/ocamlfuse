#include <caml/memory.h>
#include <caml/mlvalues.h>

extern long ml_fuse_record_exception(value exn, const char *op, value path);

CAMLprim value ocamlfuse_test_record_exception(value exn, value path) {
  CAMLparam2(exn, path);
  (void)ml_fuse_record_exception(exn, "test", path);
  CAMLreturn(Val_unit);
}
