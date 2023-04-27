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

  Vincenzo Ciancia

  applejack@users.sf.net
  vincenzo_ml@yahoo.it
*/

#include <caml/version.h>

#if OCAML_VERSION < 50000
#define CAML_NAME_SPACE
#endif

#include <unistd.h>
#include <stddef.h>
#include <string.h>
#include <errno.h>
#if defined(__APPLE__)
#include <sys/mount.h>
#else
#include <sys/vfs.h>
#endif
#include <sys/statvfs.h>

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/callback.h>
#include <caml/threads.h>
#ifdef Custom_tag
#include <caml/custom.h>
#include <caml/bigarray.h>
#endif
#include <caml/camlidlruntime.h>

int c2ml_unix_error(int c_err);

CAMLprim value unix_util_read(value fd,value buf)
{
  CAMLparam2(fd,buf);
  CAMLlocal1(vres);
  int res;
  int c_fd = Int_val(fd); /* TODO: unsafe coercion */
  void * c_data = Caml_ba_data_val(buf);
  int c_dim = Caml_ba_array_val(buf)->dim[0];

  caml_enter_blocking_section();
  res = read(c_fd, c_data, c_dim);
  caml_leave_blocking_section();
  if (res >=0)
    {
      vres=caml_alloc(1,1); /* Ok result */
      Store_field(vres,0,Val_int(res));
    }
  else
    {
      vres=caml_alloc(1,0); /* Bad result */
      Store_field(vres,0,Val_int(c2ml_unix_error(res))); /* TODO: EUNKNOWN x is a block */
    }
  CAMLreturn (vres);
}

CAMLprim value unix_util_write(value fd,value buf)
{
  CAMLparam2(fd,buf);
  CAMLlocal1(vres);
  int res;
  int c_fd = Int_val(fd); /* TODO: unsafe coercion */
  void * c_data = Caml_ba_data_val(buf);
  int c_dim = Caml_ba_array_val(buf)->dim[0];

  caml_enter_blocking_section();
  res = write(c_fd, c_data, c_dim);
  caml_leave_blocking_section();
  if (res >=0)
    {
      vres=caml_alloc(1,1); /* Ok result */
      Store_field(vres,0,Val_int(res));
    }
  else
    {
      vres=caml_alloc(1,0); /* Bad result */
      Store_field(vres,0,Val_int(c2ml_unix_error(res))); /* TODO: EUNKNOWN x is a block */
    }
  CAMLreturn (vres);
}

CAMLprim value unix_util_int_of_file_descr(value fd)
{
  CAMLparam1(fd);
  CAMLreturn (Val_int(Int_val(fd)) /* TODO: unsafe coercion */ );
}

CAMLprim value unix_util_file_descr_of_int(value fd)
{
  CAMLparam1(fd);
  CAMLreturn (Val_int(Int_val(fd) /* TODO: unsafe coercion */ ));
}

CAMLprim value unix_util_fchdir(value fd)
{
  CAMLparam1(fd);
  fchdir(Int_val(fd));
  CAMLreturn (Val_unit);
}

CAMLprim value copy_statvfs (struct statvfs *buf)
{
  CAMLparam0 ();
  CAMLlocal2 (bufv,v);
  bufv = caml_alloc (11, 0);
  v=caml_copy_int64 (buf->f_bsize);caml_modify (&Field (bufv, 0),v);
  v=caml_copy_int64 (buf->f_frsize);caml_modify (&Field (bufv, 1),v);
  v=caml_copy_int64 (buf->f_blocks);caml_modify (&Field (bufv, 2),v);
  v=caml_copy_int64 (buf->f_bfree);caml_modify (&Field (bufv, 3),v);
  v=caml_copy_int64 (buf->f_bavail);caml_modify (&Field (bufv, 4),v);
  v=caml_copy_int64 (buf->f_files);caml_modify (&Field (bufv, 5),v);
  v=caml_copy_int64 (buf->f_ffree);caml_modify (&Field (bufv, 6),v);
  v=caml_copy_int64 (buf->f_favail);caml_modify (&Field (bufv, 7),v);
  v=caml_copy_int64 (buf->f_fsid);caml_modify (&Field (bufv, 8),v);
  v=caml_copy_int64 (buf->f_flag);caml_modify (&Field (bufv, 9),v);
  caml_copy_int64 (buf->f_namemax);caml_modify (&Field (bufv, 10),v);
  CAMLreturn (bufv);
}

CAMLprim value unix_util_statvfs (value pathv)
{
  CAMLparam1 (pathv);
  CAMLlocal2 (vres,bufv);
  vres=caml_alloc(1,1); /* Ok result */
  bufv;
  const char *path = String_val (pathv);
  struct statvfs buf;
  int res;
  caml_enter_blocking_section();
  res = statvfs(path,&buf);
  caml_leave_blocking_section();
  if (res >=0)
    {
      bufv = copy_statvfs (&buf);
      Store_field(vres,0,bufv);
    }
  else
    {
      Tag_val(vres)=0; /* Bad result */
      Store_field(vres,0,Val_int(c2ml_unix_error(res))); /* TODO: EUNKNOWN x is a block */
    }
  CAMLreturn (vres);
}
