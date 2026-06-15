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

#define UNKNOWN_ERR 127

#include <caml/alloc.h>
#include <caml/bigarray.h>
#include <caml/callback.h>
#include <caml/camlidlruntime.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>
#include <caml/threads.h>

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#define FUSE_USE_VERSION 30
#include <fuse.h>
#include <fuse_lowlevel.h>
#include <sys/types.h>
#include <sys/xattr.h>

#include "Fuse_bindings.h"

#define min(a, b) (a < b ? a : b)

#ifndef RENAME_NOREPLACE
#define RENAME_NOREPLACE (1 << 0)
#endif

#ifndef RENAME_EXCHANGE
#define RENAME_EXCHANGE (1 << 1)
#endif

#ifndef RENAME_WHITEOUT
#define RENAME_WHITEOUT (1 << 2)
#endif

CAMLprim value callback4(value closure, value arg1, value arg2, value arg3,
                         value arg4) {
  CAMLparam5(closure, arg1, arg2, arg3, arg4);
  CAMLlocalN(args, 4);
  args[0] = arg1;
  args[1] = arg2;
  args[2] = arg3;
  args[3] = arg4;
  CAMLreturn(caml_callbackN(closure, 4, args));
}

CAMLprim value c2ml_setxattr_flags(int flags) {
  CAMLparam0();
  CAMLlocal1(res);

  if (flags == XATTR_CREATE) {
    res = Val_int(1);
  } else if (flags == XATTR_REPLACE) {
    res = Val_int(2);
  } else
    res = Val_int(0);

  CAMLreturn(res);
}

/* This part shamelessly copied from mlfuse */
#define ADDFLAGT(T, X)                                                         \
  num_ml_constr--;                                                             \
  if (T) {                                                                     \
    tmp = caml_alloc(2, 0);                                                    \
    Store_field(tmp, 0, Val_int(num_ml_constr));                               \
    Store_field(tmp, 1, res);                                                  \
    res = tmp;                                                                 \
  }

#define ADDFLAG(X) ADDFLAGT(flags &X, X)
#define ADDBASEFLAG(X) ADDFLAGT((flags & 3) == X, X)

CAMLprim value c_flags_to_open_flag_list(int flags) {
  CAMLparam0();
  CAMLlocal2(res, tmp);
  int num_ml_constr = 8;

  res = Val_int(0);

  ADDFLAG(O_EXCL);
  ADDFLAG(O_TRUNC);
  ADDFLAG(O_CREAT);
  ADDFLAG(O_APPEND);
  ADDFLAG(O_NONBLOCK);

  ADDBASEFLAG(O_RDWR);
  ADDBASEFLAG(O_WRONLY);
  ADDBASEFLAG(O_RDONLY);

  CAMLreturn(res);
}
/* End of shame */

static int ml2c_unix_error_vect[] = {
    E2BIG,
    EACCES,
    EAGAIN,
    EBADF,
    EBUSY,
    ECHILD,
    EDEADLK,
    EDOM,
    EEXIST,
    EFAULT,
    EFBIG,
    EINTR,
    EINVAL,
    EIO,
    EISDIR,
    EMFILE,
    EMLINK,
    ENAMETOOLONG,
    ENFILE,
    ENODEV,
    ENOENT,
    ENOEXEC,
    ENOLCK,
    ENOMEM,
    ENOSPC,
    ENOSYS,
    ENOTDIR,
    ENOTEMPTY,
    ENOTTY,
    ENXIO,
    EPERM,
    EPIPE,
    ERANGE,
    EROFS,
    ESPIPE,
    ESRCH,
    EXDEV,
    EWOULDBLOCK,
    EINPROGRESS,
    EALREADY,
    ENOTSOCK,
    EDESTADDRREQ,
    EMSGSIZE,
    EPROTOTYPE,
    ENOPROTOOPT,
    EPROTONOSUPPORT,
    ESOCKTNOSUPPORT,
    EOPNOTSUPP,
    EPFNOSUPPORT,
    EAFNOSUPPORT,
    EADDRINUSE,
    EADDRNOTAVAIL,
    ENETDOWN,
    ENETUNREACH,
    ENETRESET,
    ECONNABORTED,
    ECONNRESET,
    ENOBUFS,
    EISCONN,
    ENOTCONN,
    ESHUTDOWN,
    ETOOMANYREFS,
    ETIMEDOUT,
    ECONNREFUSED,
    EHOSTDOWN,
    EHOSTUNREACH,
    ELOOP,
    EOVERFLOW,
    0 /* Terminator for the inverse function */
};

static int ml2c_unix_error_vect_dim = 0;

int ml2c_unix_error(int ocaml_err) {
  if (ocaml_err < ml2c_unix_error_vect_dim)
    return ml2c_unix_error_vect[ocaml_err];
  return UNKNOWN_ERR; /* TODO: find an appropriate value */
}

/* TODO: This sucks */

int *invert_array(int *src, int *indim, int *outdim) {
  /* Find dimensions */
  int dim = 0;
  int i = 0;
  int srcdim = 0;

  while (src[srcdim] != 0) {
    if (src[srcdim] + 1 > dim)
      dim = src[srcdim] + 1;
    srcdim++;
  }

  /* Create the result */
  int *res = malloc(dim * sizeof(int));
  for (i = 0; i < dim; i++)
    res[i] = UNKNOWN_ERR; /* TODO: find a meaningful value */

  /* Invert the array */
  for (i = 0; i < srcdim; i++)
    res[src[i]] = i;

  *indim = srcdim;
  *outdim = dim;
  return res;
}

static int c2ml_unix_error_vect_dim = 0;
static int *c2ml_unix_error_vect;

int c2ml_unix_error(int c_err) {
  if (c_err < c2ml_unix_error_vect_dim)
    return c2ml_unix_error_vect[c_err];
  return UNKNOWN_ERR; /* TODO: find a meaningful value (also search for
                         UNKNOWN_ERR in this file */
}

static value make_bad_unix_error(int c_err) {
  CAMLparam0();
  CAMLlocal1(vres);
  vres = caml_alloc(1, 0);
  Store_field(vres, 0, Val_int(c2ml_unix_error(c_err)));
  CAMLreturn(vres);
}

/* end "Thisk sucks" part */

int ml2c_unix_file_kind[] = {S_IFREG, S_IFDIR, S_IFCHR, S_IFBLK,
                             S_IFLNK, S_IFIFO, S_IFSOCK};

void ml2c_Unix_stats_struct_stat(value v, struct stat *s) {
  CAMLparam1(v);
  memset(s, 0, sizeof(*s));
  s->st_dev = Int_val(Field(v, 0));
  s->st_ino = Int_val(Field(v, 1));
  s->st_mode =
      0 | Int_val(Field(v, 3)) | ml2c_unix_file_kind[Int_val(Field(v, 2))];
  s->st_nlink = Int_val(Field(v, 4));
  s->st_uid = Int_val(Field(v, 5));
  s->st_gid = Int_val(Field(v, 6));
  s->st_rdev = Int_val(Field(v, 7));
  s->st_size = Int64_val(Field(v, 8));
  s->st_blksize = 512; /* TODO: STUB, at least use the one from statfs */
  s->st_blocks =
      ceil(((double)s->st_size) / ((double)s->st_blksize)); /* TODO: STUB! */
  s->st_atime = Double_val(Field(v, 9));
  s->st_mtime = Double_val(Field(v, 10));
  s->st_ctime = Double_val(Field(v, 11));
  CAMLreturn0;
}

void ml2c_Unix_struct_statvfs(value v, struct statvfs *st) {
  CAMLparam1(v);
  memset(st, 0, sizeof(*st));
  st->f_bsize = Int64_val(Field(v, 0));
  st->f_frsize = Int64_val(Field(v, 1));
  st->f_blocks = Int64_val(Field(v, 2));
  st->f_bfree = Int64_val(Field(v, 3));
  st->f_bavail = Int64_val(Field(v, 4));
  st->f_files = Int64_val(Field(v, 5));
  st->f_ffree = Int64_val(Field(v, 6));
  st->f_favail = Int64_val(Field(v, 7));
  st->f_fsid = Int64_val(Field(v, 8));
  st->f_flag = Int64_val(Field(v, 9));
  st->f_namemax = Int64_val(Field(v, 10));
  CAMLreturn0;
  /* TODO: check the meaning of the following missing field:
     __f_spare
  */
}

static value make_some(value v) {
  CAMLparam1(v);
  CAMLlocal1(vres);
  vres = caml_alloc(1, 0);
  Store_field(vres, 0, v);
  CAMLreturn(vres);
}

static value c2ml_file_info(const struct fuse_file_info *fi) {
  CAMLparam0();
  CAMLlocal1(vres);

  vres = caml_alloc(13, 0);
  Store_field(vres, 0, c_flags_to_open_flag_list(fi->flags));
  Store_field(vres, 1, Val_int(fi->flags));
  Store_field(vres, 2, caml_copy_int64((int64_t)fi->fh));
  Store_field(vres, 3, Val_bool(fi->writepage));
  Store_field(vres, 4, Val_bool(fi->direct_io));
  Store_field(vres, 5, Val_bool(fi->keep_cache));
  Store_field(vres, 6, Val_bool(fi->flush));
  Store_field(vres, 7, Val_bool(fi->nonseekable));
  Store_field(vres, 8, Val_bool(fi->flock_release));
  Store_field(vres, 9, Val_bool(fi->cache_readdir));
  Store_field(vres, 10, Val_bool(fi->noflush));
  Store_field(vres, 11, caml_copy_int64((int64_t)fi->lock_owner));
  Store_field(vres, 12, caml_copy_int32((int32_t)fi->poll_events));
  CAMLreturn(vres);
}

static value c2ml_file_info_option(const struct fuse_file_info *fi) {
  CAMLparam0();
  CAMLlocal1(vfi);

  if (fi == NULL)
    CAMLreturn(Val_int(0));

  vfi = c2ml_file_info(fi);
  CAMLreturn(make_some(vfi));
}

static void ml2c_file_info_update(struct fuse_file_info *fi, value vupdate,
                                  int is_dir) {
  CAMLparam1(vupdate);
  value vfh;

  if (fi == NULL)
    CAMLreturn0;

  vfh = Field(vupdate, 0);
  if (Is_block(vfh))
    fi->fh = (uint64_t)Int64_val(Field(vfh, 0));

  if (is_dir) {
    fi->cache_readdir = Bool_val(Field(vupdate, 4));
  } else {
    fi->direct_io = Bool_val(Field(vupdate, 1));
    fi->keep_cache = Bool_val(Field(vupdate, 2));
    fi->nonseekable = Bool_val(Field(vupdate, 3));
    fi->noflush = Bool_val(Field(vupdate, 5));
  }

  CAMLreturn0;
}

static value c2ml_rename_flags(unsigned int flags) {
  CAMLparam0();
  CAMLlocal1(vres);

  vres = caml_alloc(4, 0);
  Store_field(vres, 0, Val_bool(flags & RENAME_NOREPLACE));
  Store_field(vres, 1, Val_bool(flags & RENAME_EXCHANGE));
  Store_field(vres, 2, Val_bool(flags & RENAME_WHITEOUT));
  Store_field(vres, 3, Val_int(flags));
  CAMLreturn(vres);
}

static value c2ml_readdir_flags(enum fuse_readdir_flags flags) {
  CAMLparam0();
  CAMLlocal1(vres);

  vres = caml_alloc(2, 0);
  Store_field(vres, 0, Val_bool(flags & FUSE_READDIR_PLUS));
  Store_field(vres, 1, Val_int(flags));
  CAMLreturn(vres);
}

static value c2ml_timestamp(const struct timespec *tv) {
  CAMLparam0();
  CAMLlocal2(vtimespec, vres);

  if (tv->tv_nsec == UTIME_NOW)
    CAMLreturn(Val_int(0));
  if (tv->tv_nsec == UTIME_OMIT)
    CAMLreturn(Val_int(1));

  vtimespec = caml_alloc(2, 0);
  Store_field(vtimespec, 0, caml_copy_int64((int64_t)tv->tv_sec));
  Store_field(vtimespec, 1, Val_int(tv->tv_nsec));
  vres = caml_alloc(1, 0);
  Store_field(vres, 0, vtimespec);
  CAMLreturn(vres);
}

static enum fuse_fill_dir_flags ml2c_fill_dir_flags(value vflags) {
  enum fuse_fill_dir_flags flags = 0;
  if (Bool_val(Field(vflags, 0)))
    flags |= FUSE_FILL_DIR_PLUS;
  return flags;
}

#define FOR_ALL_NON_INIT_OPS(MACRO)                                            \
  MACRO(getattr)                                                               \
  MACRO(readlink)                                                              \
  MACRO(readdir)                                                               \
  MACRO(opendir)                                                               \
  MACRO(releasedir)                                                            \
  MACRO(fsyncdir)                                                              \
  MACRO(mknod)                                                                 \
  MACRO(mkdir)                                                                 \
  MACRO(symlink)                                                               \
  MACRO(unlink)                                                                \
  MACRO(rmdir)                                                                 \
  MACRO(rename)                                                                \
  MACRO(link)                                                                  \
  MACRO(chmod)                                                                 \
  MACRO(chown)                                                                 \
  MACRO(truncate)                                                              \
  MACRO(utimens)                                                               \
  MACRO(open)                                                                  \
  MACRO(read)                                                                  \
  MACRO(write)                                                                 \
  MACRO(statfs)                                                                \
  MACRO(release)                                                               \
  MACRO(flush)                                                                 \
  MACRO(fsync)                                                                 \
  MACRO(setxattr)                                                              \
  MACRO(getxattr)                                                              \
  MACRO(listxattr)                                                             \
  MACRO(removexattr)

#define FOR_ALL_OPS(MACRO)                                                     \
  MACRO(init)                                                                  \
  FOR_ALL_NON_INIT_OPS(MACRO)

/*
   TODO: missing callbacks for fuse API version 2.7

   CALLS INTRODUCED FROM 2.3 ON

   unsigned int 	flag_nullpath_ok: 1
   void(* 	destroy )(void *)
   int(* 	access )(const char *, int)
   int(* 	create )(const char *, mode_t, struct fuse_file_info *)
   int(* 	ftruncate )(const char *, off_t, struct fuse_file_info *)
   int(* 	fgetattr )(const char *, struct stat *, struct fuse_file_info *)
   int(* 	lock )(const char *, struct fuse_file_info *, int cmd, struct
   flock *) int(* 	utimens )(const char *, const struct timespec tv[2])
   int(* 	bmap )(const char *, size_t blocksize, uint64_t *idx)
   int(* 	ioctl )(const char *, int cmd, void *arg, struct fuse_file_info
   *, unsigned int flags, void *data) int(* 	poll )(const char *, struct
   fuse_file_info *, struct fuse_pollhandle *ph, unsigned *reventsp)
*/

#define SET_NULL_OP(OPNAME) .OPNAME = NULL,

static struct fuse_operations ops = {FOR_ALL_OPS(SET_NULL_OP)};

enum ml_fuse_thread_kind {
  ML_FUSE_THREAD_NONE = 0,
  ML_FUSE_THREAD_OCAML_OWNED = 1,
  ML_FUSE_THREAD_REGISTERED_BY_BINDING = 2,
};

static pthread_once_t ml_fuse_thread_key_once = PTHREAD_ONCE_INIT;
static pthread_key_t ml_fuse_thread_key;
static int ml_fuse_thread_key_created = 0;
static pthread_mutex_t ml_fuse_thread_registration_lock =
    PTHREAD_MUTEX_INITIALIZER;
static int ml_fuse_thread_registration_failed = 0;

static void ml_fuse_record_thread_registration_failure() {
  pthread_mutex_lock(&ml_fuse_thread_registration_lock);
  ml_fuse_thread_registration_failed = 1;
  pthread_mutex_unlock(&ml_fuse_thread_registration_lock);
}

static int ml_fuse_thread_registration_has_failed() {
  int failed;

  pthread_mutex_lock(&ml_fuse_thread_registration_lock);
  failed = ml_fuse_thread_registration_failed;
  pthread_mutex_unlock(&ml_fuse_thread_registration_lock);

  return failed;
}

static void ml_fuse_reset_thread_registration_failure() {
  pthread_mutex_lock(&ml_fuse_thread_registration_lock);
  ml_fuse_thread_registration_failed = 0;
  pthread_mutex_unlock(&ml_fuse_thread_registration_lock);
}

static void ml_fuse_thread_key_destructor(void *value) {
  if ((intptr_t)value == ML_FUSE_THREAD_REGISTERED_BY_BINDING)
    (void)caml_c_thread_unregister();
}

static void ml_fuse_make_thread_key() {
  if (pthread_key_create(&ml_fuse_thread_key, ml_fuse_thread_key_destructor) ==
      0)
    ml_fuse_thread_key_created = 1;
  else
    ml_fuse_record_thread_registration_failure();
}

static int ml_fuse_ensure_thread_key() {
  if (pthread_once(&ml_fuse_thread_key_once, ml_fuse_make_thread_key) != 0)
    ml_fuse_record_thread_registration_failure();

  return ml_fuse_thread_key_created ? 0 : -1;
}

static int ml_fuse_set_thread_kind(enum ml_fuse_thread_kind kind) {
  if (ml_fuse_ensure_thread_key() != 0)
    return -1;

  if (pthread_setspecific(ml_fuse_thread_key, (void *)(intptr_t)kind) != 0) {
    ml_fuse_record_thread_registration_failure();
    return -1;
  }

  return 0;
}

static int ml_fuse_mark_ocaml_thread() {
  return ml_fuse_set_thread_kind(ML_FUSE_THREAD_OCAML_OWNED);
}

static void ml_fuse_clear_thread_kind() {
  if (ml_fuse_thread_key_created)
    (void)pthread_setspecific(ml_fuse_thread_key, NULL);
}

static int ml_fuse_enter_ocaml_callback() {
  enum ml_fuse_thread_kind kind;

  if (ml_fuse_ensure_thread_key() != 0)
    return -1;

  kind = (enum ml_fuse_thread_kind)(intptr_t)pthread_getspecific(
      ml_fuse_thread_key);
  if (kind == ML_FUSE_THREAD_NONE) {
    if (caml_c_thread_register() == 0) {
      ml_fuse_record_thread_registration_failure();
      return -1;
    }

    if (pthread_setspecific(
            ml_fuse_thread_key,
            (void *)(intptr_t)ML_FUSE_THREAD_REGISTERED_BY_BINDING) != 0) {
      (void)caml_c_thread_unregister();
      ml_fuse_record_thread_registration_failure();
      return -1;
    }
  }

  caml_acquire_runtime_system();
  return 0;
}

static void ml_fuse_leave_ocaml_callback() { caml_release_runtime_system(); }

#define DECLARE_OP_CLOSURE(OPNAME) static const value *OPNAME##_closure = NULL;
FOR_ALL_OPS(DECLARE_OP_CLOSURE)

#define getattr_ARGS                                                           \
  (const char *path, struct stat *buf, struct fuse_file_info *fi)
#define getattr_CALL_ARGS (path, buf, fi)
#define getattr_RTYPE int
#define getattr_CB                                                             \
  if (path == NULL) {                                                          \
    vres = make_bad_unix_error(EINVAL);                                        \
  } else {                                                                     \
    vpath = caml_copy_string(path);                                            \
    vfi = c2ml_file_info_option(fi);                                           \
    vres = caml_callback2(*getattr_closure, vpath, vfi);                       \
  }
#define getattr_RES ml2c_Unix_stats_struct_stat(Field(vres, 0), buf);

#define readdir_ARGS                                                           \
  (const char *path, void *buf, fuse_fill_dir_t filler, off_t offset,          \
   struct fuse_file_info *info, enum fuse_readdir_flags flags)
#define readdir_CALL_ARGS (path, buf, filler, offset, info, flags)
#define readdir_RTYPE int
#define readdir_CB                                                             \
  if (path == NULL || info == NULL) {                                          \
    vres = make_bad_unix_error(EINVAL);                                        \
  } else {                                                                     \
    vpath = caml_copy_string(path);                                            \
    vfi = c2ml_file_info(info);                                                \
    vflags = c2ml_readdir_flags(flags);                                        \
    vres = callback4(*readdir_closure, vpath, caml_copy_int64(offset), vfi,    \
                     vflags);                                                  \
  }
#define readdir_RES                                                            \
  vtmp = Field(vres, 0);                                                       \
  while (Is_block(vtmp)) {                                                     \
    struct stat stbuf;                                                         \
    struct stat *stbuf_ptr = NULL;                                             \
    off_t entry_offset = 0;                                                    \
    enum fuse_fill_dir_flags entry_flags;                                      \
    ventry = Field(vtmp, 0);                                                   \
    vstat = Field(ventry, 1);                                                  \
    if (Is_block(vstat)) {                                                     \
      ml2c_Unix_stats_struct_stat(Field(vstat, 0), &stbuf);                    \
      stbuf_ptr = &stbuf;                                                      \
    }                                                                          \
    voffset = Field(ventry, 2);                                                \
    if (Is_block(voffset))                                                     \
      entry_offset = (off_t)Int64_val(Field(voffset, 0));                      \
    entry_flags = ml2c_fill_dir_flags(Field(ventry, 3));                       \
    if (filler(buf, String_val(Field(ventry, 0)), stbuf_ptr, entry_offset,     \
               entry_flags))                                                   \
      break;                                                                   \
    if (res != 0)                                                              \
      break;                                                                   \
    vtmp = Field(vtmp, 1);                                                     \
  }

#define mknod_ARGS (const char *path, mode_t mode, dev_t rdev)
#define mknod_CALL_ARGS (path, mode, rdev)
#define mknod_RTYPE int
#define mknod_CB                                                               \
  vpath = caml_copy_string(path);                                              \
  vres = caml_callback2(*mknod_closure, vpath, Val_int(mode));
#define mknod_RES

#define mkdir_ARGS (const char *path, mode_t mode)
#define mkdir_CALL_ARGS (path, mode)
#define mkdir_RTYPE int
#define mkdir_CB                                                               \
  vpath = caml_copy_string(path);                                              \
  vres = caml_callback2(*mkdir_closure, vpath, Val_int(mode));
#define mkdir_RES

#define unlink_ARGS (const char *path)
#define unlink_CALL_ARGS (path)
#define unlink_RTYPE int
#define unlink_CB                                                              \
  vpath = caml_copy_string(path);                                              \
  vres = caml_callback(*unlink_closure, vpath);
#define unlink_RES

#define rmdir_ARGS (const char *path)
#define rmdir_CALL_ARGS (path)
#define rmdir_RTYPE int
#define rmdir_CB                                                               \
  vpath = caml_copy_string(path);                                              \
  vres = caml_callback(*rmdir_closure, vpath);
#define rmdir_RES

#define readlink_ARGS (const char *path, char *buf, size_t size)
#define readlink_CALL_ARGS (path, buf, size)
#define readlink_RTYPE int
#define readlink_CB                                                            \
  vpath = caml_copy_string(path);                                              \
  vres = caml_callback(*readlink_closure, vpath);
#define readlink_RES strncpy(buf, String_val(Field(vres, 0)), size - 1);

#define symlink_ARGS (const char *path, const char *dest)
#define symlink_CALL_ARGS (path, dest)
#define symlink_RTYPE int
#define symlink_CB                                                             \
  vpath = caml_copy_string(path);                                              \
  vtmp = caml_copy_string(dest);                                               \
  vres = caml_callback2(*symlink_closure, vpath, vtmp);
#define symlink_RES

#define rename_ARGS (const char *path, const char *dest, unsigned int flags)
#define rename_CALL_ARGS (path, dest, flags)
#define rename_RTYPE int
#define rename_CB                                                              \
  if (path == NULL || dest == NULL) {                                          \
    vres = make_bad_unix_error(EINVAL);                                        \
  } else {                                                                     \
    vpath = caml_copy_string(path);                                            \
    vtmp = caml_copy_string(dest);                                             \
    vflags = c2ml_rename_flags(flags);                                         \
    vres = caml_callback3(*rename_closure, vpath, vtmp, vflags);               \
  }
#define rename_RES

#define link_ARGS (const char *path, const char *dest)
#define link_CALL_ARGS (path, dest)
#define link_RTYPE int
#define link_CB                                                                \
  vpath = caml_copy_string(path);                                              \
  vtmp = caml_copy_string(dest);                                               \
  vres = caml_callback2(*link_closure, vpath, vtmp);
#define link_RES

#define chmod_ARGS (const char *path, mode_t mode, struct fuse_file_info *fi)
#define chmod_CALL_ARGS (path, mode, fi)
#define chmod_RTYPE int
#define chmod_CB                                                               \
  if (path == NULL) {                                                          \
    vres = make_bad_unix_error(EINVAL);                                        \
  } else {                                                                     \
    vpath = caml_copy_string(path);                                            \
    vfi = c2ml_file_info_option(fi);                                           \
    vres = caml_callback3(*chmod_closure, vpath, Val_int(mode), vfi);          \
  }
#define chmod_RES

#define chown_ARGS                                                             \
  (const char *path, uid_t uid, gid_t gid, struct fuse_file_info *fi)
#define chown_CALL_ARGS (path, uid, gid, fi)
#define chown_RTYPE int
#define chown_CB                                                               \
  if (path == NULL) {                                                          \
    vres = make_bad_unix_error(EINVAL);                                        \
  } else {                                                                     \
    vpath = caml_copy_string(path);                                            \
    vfi = c2ml_file_info_option(fi);                                           \
    vres = callback4(*chown_closure, vpath, Val_int(uid), Val_int(gid), vfi);  \
  }
#define chown_RES

#define truncate_ARGS (const char *path, off_t size, struct fuse_file_info *fi)
#define truncate_CALL_ARGS (path, size, fi)
#define truncate_RTYPE int
#define truncate_CB                                                            \
  if (path == NULL) {                                                          \
    vres = make_bad_unix_error(EINVAL);                                        \
  } else {                                                                     \
    vpath = caml_copy_string(path);                                            \
    vfi = c2ml_file_info_option(fi);                                           \
    vres =                                                                     \
        caml_callback3(*truncate_closure, vpath, caml_copy_int64(size), vfi);  \
  }
#define truncate_RES

#define utimens_ARGS                                                           \
  (const char *path, const struct timespec tv[2], struct fuse_file_info *fi)
#define utimens_CALL_ARGS (path, tv, fi)
#define utimens_RTYPE int
#define utimens_CB                                                             \
  if (path == NULL) {                                                          \
    vres = make_bad_unix_error(EINVAL);                                        \
  } else {                                                                     \
    vpath = caml_copy_string(path);                                            \
    vtmp = c2ml_timestamp(&tv[0]);                                             \
    vtmp2 = c2ml_timestamp(&tv[1]);                                            \
    vfi = c2ml_file_info_option(fi);                                           \
    vres = callback4(*utimens_closure, vpath, vtmp, vtmp2, vfi);               \
  }
#define utimens_RES

#define open_ARGS (const char *path, struct fuse_file_info *fi)
#define open_CALL_ARGS (path, fi)
#define open_RTYPE int
#define open_CB                                                                \
  if (path == NULL || fi == NULL) {                                            \
    vres = make_bad_unix_error(EINVAL);                                        \
  } else {                                                                     \
    vpath = caml_copy_string(path);                                            \
    vfi = c2ml_file_info(fi);                                                  \
    vres = caml_callback2(*open_closure, vpath, vfi);                          \
  }
#define open_RES ml2c_file_info_update(fi, Field(vres, 0), 0);

#define opendir_ARGS (const char *path, struct fuse_file_info *fi)
#define opendir_CALL_ARGS (path, fi)
#define opendir_RTYPE int
#define opendir_CB                                                             \
  if (path == NULL || fi == NULL) {                                            \
    vres = make_bad_unix_error(EINVAL);                                        \
  } else {                                                                     \
    vpath = caml_copy_string(path);                                            \
    vfi = c2ml_file_info(fi);                                                  \
    vres = caml_callback2(*opendir_closure, vpath, vfi);                       \
  }
#define opendir_RES ml2c_file_info_update(fi, Field(vres, 0), 1);

#define read_ARGS                                                              \
  (const char *path, char *buf, size_t size, off_t offset,                     \
   struct fuse_file_info *fi)
#define read_CALL_ARGS (path, buf, size, offset, fi)
#define read_RTYPE int
#define read_CB                                                                \
  if (path == NULL || fi == NULL) {                                            \
    vres = make_bad_unix_error(EINVAL);                                        \
  } else {                                                                     \
    vpath = caml_copy_string(path);                                            \
    vfi = c2ml_file_info(fi);                                                  \
    vres = callback4(                                                          \
        *read_closure, vpath,                                                  \
        caml_ba_alloc_dims(CAML_BA_UINT8 | CAML_BA_C_LAYOUT, 1, buf, size),    \
        caml_copy_int64(offset), vfi);                                         \
  }
#define read_RES res = Int_val(Field(vres, 0));

#define write_ARGS                                                             \
  (const char *path, const char *buf, size_t size, off_t offset,               \
   struct fuse_file_info                                                       \
       *fi) /* TODO: check usage of the writepages field of fi */
#define write_CALL_ARGS (path, buf, size, offset, fi)
#define write_RTYPE int
#define write_CB                                                               \
  if (path == NULL || fi == NULL) {                                            \
    vres = make_bad_unix_error(EINVAL);                                        \
  } else {                                                                     \
    vpath = caml_copy_string(path);                                            \
    vfi = c2ml_file_info(fi);                                                  \
    vres = callback4(*write_closure, vpath,                                    \
                     caml_ba_alloc_dims(CAML_BA_UINT8 | CAML_BA_C_LAYOUT, 1,   \
                                        (char *)buf, size),                    \
                     caml_copy_int64(offset), vfi);                            \
  }
#define write_RES res = Int_val(Field(vres, 0));

#define release_ARGS (const char *path, struct fuse_file_info *fi)
#define release_CALL_ARGS (path, fi)
#define release_RTYPE int
#define release_CB                                                             \
  if (path == NULL || fi == NULL) {                                            \
    vres = make_bad_unix_error(EINVAL);                                        \
  } else {                                                                     \
    vpath = caml_copy_string(path);                                            \
    vfi = c2ml_file_info(fi);                                                  \
    vres = caml_callback2(*release_closure, vpath, vfi);                       \
  }
#define release_RES

#define releasedir_ARGS (const char *path, struct fuse_file_info *fi)
#define releasedir_CALL_ARGS (path, fi)
#define releasedir_RTYPE int
#define releasedir_CB                                                          \
  if (path == NULL || fi == NULL) {                                            \
    vres = make_bad_unix_error(EINVAL);                                        \
  } else {                                                                     \
    vpath = caml_copy_string(path);                                            \
    vfi = c2ml_file_info(fi);                                                  \
    vres = caml_callback2(*releasedir_closure, vpath, vfi);                    \
  }
#define releasedir_RES

#define flush_ARGS (const char *path, struct fuse_file_info *fi)
#define flush_CALL_ARGS (path, fi)
#define flush_RTYPE int
#define flush_CB                                                               \
  if (path == NULL || fi == NULL) {                                            \
    vres = make_bad_unix_error(EINVAL);                                        \
  } else {                                                                     \
    vpath = caml_copy_string(path);                                            \
    vfi = c2ml_file_info(fi);                                                  \
    vres = caml_callback2(*flush_closure, vpath, vfi);                         \
  }
#define flush_RES

#define statfs_ARGS (const char *path, struct statvfs *stbuf)
#define statfs_CALL_ARGS (path, stbuf)
#define statfs_RTYPE int
#define statfs_CB                                                              \
  vpath = caml_copy_string(path);                                              \
  vres = caml_callback(*statfs_closure, vpath);
#define statfs_RES ml2c_Unix_struct_statvfs(Field(vres, 0), stbuf);

#define fsync_ARGS (const char *path, int isdatasync, struct fuse_file_info *fi)
#define fsync_CALL_ARGS (path, isdatasync, fi)
#define fsync_RTYPE int
#define fsync_CB                                                               \
  if (path == NULL || fi == NULL) {                                            \
    vres = make_bad_unix_error(EINVAL);                                        \
  } else {                                                                     \
    vpath = caml_copy_string(path);                                            \
    vfi = c2ml_file_info(fi);                                                  \
    vres = caml_callback3(*fsync_closure, vpath, Val_bool(isdatasync), vfi);   \
  }
#define fsync_RES

#define fsyncdir_ARGS                                                          \
  (const char *path, int isdatasync, struct fuse_file_info *fi)
#define fsyncdir_CALL_ARGS (path, isdatasync, fi)
#define fsyncdir_RTYPE int
#define fsyncdir_CB                                                            \
  if (path == NULL || fi == NULL) {                                            \
    vres = make_bad_unix_error(EINVAL);                                        \
  } else {                                                                     \
    vpath = caml_copy_string(path);                                            \
    vfi = c2ml_file_info(fi);                                                  \
    vres =                                                                     \
        caml_callback3(*fsyncdir_closure, vpath, Val_bool(isdatasync), vfi);   \
  }
#define fsyncdir_RES

#define setxattr_ARGS                                                          \
  (const char *path, const char *name, const char *val, size_t size, int flags)
#define setxattr_CALL_ARGS (path, name, val, size, flags)
#define setxattr_RTYPE int
#define setxattr_CB                                                            \
  vpath = caml_copy_string(path);                                              \
  vstring = caml_alloc_string(size);                                           \
  memcpy(&Byte(String_val(vstring), 0), val, size);                            \
  vres = callback4(*setxattr_closure, vpath, caml_copy_string(name), vstring,  \
                   c2ml_setxattr_flags(flags));
#define setxattr_RES

#define getxattr_ARGS                                                          \
  (const char *path, const char *name, char *val, size_t size)
#define getxattr_CALL_ARGS (path, name, val, size)
#define getxattr_RTYPE int
#define getxattr_CB                                                            \
  vpath = caml_copy_string(path);                                              \
  vres = caml_callback2(*getxattr_closure, vpath, caml_copy_string(name));
#define getxattr_RES                                                           \
  res = caml_string_length(Field(vres, 0));                                    \
  if (size > 0) {                                                              \
    if (caml_string_length(Field(vres, 0)) > size) {                           \
      res = -ERANGE;                                                           \
    } else {                                                                   \
      memcpy(val, String_val(Field(vres, 0)),                                  \
             caml_string_length(Field(vres, 0)));                              \
    }                                                                          \
  }

#define listxattr_ARGS (const char *path, char *list, size_t size)
#define listxattr_CALL_ARGS (path, list, size)
#define listxattr_RTYPE int
#define listxattr_CB                                                           \
  vpath = caml_copy_string(path);                                              \
  vres = caml_callback(*listxattr_closure, vpath);
#define listxattr_RES                                                          \
  vtmp = Field(Field(vres, 0), 0);                                             \
  int len;                                                                     \
  char *dest = list;                                                           \
  int rem = size;                                                              \
  if (size == 0) {                                                             \
    res = Int_val(Field(Field(vres, 0), 1));                                   \
  } else {                                                                     \
    while (Is_block(vtmp)) {                                                   \
      len = caml_string_length(Field(vtmp, 0)) + 1;                            \
      if (rem >= len) {                                                        \
        memcpy(dest, String_val(Field(vtmp, 0)), len);                         \
        vtmp = Field(vtmp, 1);                                                 \
        dest += len;                                                           \
        rem = rem - len;                                                       \
      } else {                                                                 \
        res = -ERANGE;                                                         \
        break;                                                                 \
      }                                                                        \
    }                                                                          \
    res = size - rem;                                                          \
  }

#define removexattr_ARGS (const char *path, const char *name)
#define removexattr_CALL_ARGS (path, name)
#define removexattr_RTYPE int
#define removexattr_CB                                                         \
  vpath = caml_copy_string(path);                                              \
  vres = caml_callback2(*removexattr_closure, vpath, caml_copy_string(name));
#define removexattr_RES

static void *gm281_ops_init(struct fuse_conn_info *conn,
                            struct fuse_config *cfg) {
  CAMLparam0();
  CAMLlocal1(vres);
  (void)conn;
  (void)cfg;
  vres = caml_callback(*init_closure, Val_unit);
  (void)vres;
  CAMLreturnT(void *, NULL);
}

static void *ops_init(struct fuse_conn_info *conn, struct fuse_config *cfg) {
  if (ml_fuse_enter_ocaml_callback() != 0)
    return NULL;

  void *ret = gm281_ops_init(conn, cfg);
  ml_fuse_leave_ocaml_callback();
  return ret;
}

#define CALLBACK(OPNAME)                                                       \
  static OPNAME##_RTYPE gm281_ops_##OPNAME OPNAME##_ARGS {                     \
    CAMLparam0();                                                              \
    CAMLlocal5(vstring, vpath, vres, vtmp, vtmp2);                             \
    CAMLlocal5(vfi, vflags, ventry, vstat, voffset);                           \
    OPNAME##_RTYPE res = (typeof(res))-1L;                                     \
    OPNAME##_CB if (Tag_val(vres) == 1) /* Result is not Bad */                \
    {                                                                          \
      res = (typeof(res))0L;                                                   \
      OPNAME##_RES /* res can be changed here */                               \
    }                                                                          \
    else {                                                                     \
      if (Is_block(Field(vres, 0))) /* This is EUNKNOWNERR of int in ocaml */  \
        res = (typeof(res))(long)-Int_val(Field(Field(vres, 0), 0));           \
      else                                                                     \
        res = (typeof(res))(long)-ml2c_unix_error(Int_val(Field(vres, 0)));    \
    }                                                                          \
    CAMLreturnT(OPNAME##_RTYPE, res);                                          \
  }                                                                            \
                                                                               \
  static OPNAME##_RTYPE ops_##OPNAME OPNAME##_ARGS {                           \
    if (ml_fuse_enter_ocaml_callback() != 0)                                   \
      return (OPNAME##_RTYPE) - EIO;                                           \
    OPNAME##_RTYPE ret = gm281_ops_##OPNAME OPNAME##_CALL_ARGS;                \
    ml_fuse_leave_ocaml_callback();                                            \
    return ret;                                                                \
  }

FOR_ALL_NON_INIT_OPS(CALLBACK)

#define SET_OPERATION(OPNAME)                                                  \
  if (op->OPNAME == NULL)                                                      \
    ops.OPNAME = NULL;                                                         \
  else {                                                                       \
    OPNAME##_closure = caml_named_value(op->OPNAME);                           \
    ops.OPNAME = ops_##OPNAME;                                                 \
  }

void set_fuse_operations(struct fuse_operation_names const *op) {
  FOR_ALL_OPS(SET_OPERATION)
}

struct fuse_operations *get_fuse_operations() { return &ops; }

void ml_fuse_init() {
  c2ml_unix_error_vect = invert_array(
      ml2c_unix_error_vect, &ml2c_unix_error_vect_dim,
      &c2ml_unix_error_vect_dim); /* TODO: this sucks together with the one at
                                     the beginning of file */
}

enum ml_fuse_main_status {
  ML_FUSE_MAIN_OK = 0,
  ML_FUSE_MAIN_CMDLINE = 1,
  ML_FUSE_MAIN_NO_MOUNTPOINT = 2,
  ML_FUSE_MAIN_NEW = 3,
  ML_FUSE_MAIN_MOUNT = 4,
  ML_FUSE_MAIN_DAEMONIZE = 5,
  ML_FUSE_MAIN_SIGNAL_HANDLERS = 6,
  ML_FUSE_MAIN_LOOP = 7,
  ML_FUSE_MAIN_THREAD_REGISTRATION = 8,
};

enum ml_fuse_loop_mode {
  ML_FUSE_LOOP_SINGLE_THREADED = 0,
  ML_FUSE_LOOP_MULTI_THREADED = 1,
};

int ml_fuse_main(int argc, str *argv, struct fuse_operations const *op,
                 int loop_mode) {
  struct fuse_args args = FUSE_ARGS_INIT(argc, argv);
  struct fuse_cmdline_opts opts;
  struct fuse *fuse = NULL;
  struct fuse_session *session = NULL;
  int loop_result;
  int status = ML_FUSE_MAIN_OK;
  int signal_handlers_set = 0;
  int mounted = 0;

  memset(&opts, 0, sizeof(opts));

  if (fuse_parse_cmdline(&args, &opts) != 0) {
    status = ML_FUSE_MAIN_CMDLINE;
    goto out_args;
  }

  if (opts.show_version) {
    printf("FUSE library version %s\n", fuse_pkgversion());
    fuse_lowlevel_version();
    goto out_opts;
  }

  if (opts.show_help) {
    fuse_cmdline_help();
    fuse_lib_help(&args);
    goto out_opts;
  }

  if (opts.mountpoint == NULL) {
    status = ML_FUSE_MAIN_NO_MOUNTPOINT;
    goto out_opts;
  }

  if (opts.singlethread)
    loop_mode = ML_FUSE_LOOP_SINGLE_THREADED;

  fuse = fuse_new(&args, op, sizeof(*op), NULL);
  if (fuse == NULL) {
    status = ML_FUSE_MAIN_NEW;
    goto out_opts;
  }

  if (fuse_mount(fuse, opts.mountpoint) != 0) {
    status = ML_FUSE_MAIN_MOUNT;
    goto out_destroy;
  }
  mounted = 1;

  if (fuse_daemonize(1) != 0) {
    status = ML_FUSE_MAIN_DAEMONIZE;
    goto out_unmount;
  }

  session = fuse_get_session(fuse);
  if (fuse_set_signal_handlers(session) != 0) {
    status = ML_FUSE_MAIN_SIGNAL_HANDLERS;
    goto out_unmount;
  }
  signal_handlers_set = 1;

  ml_fuse_reset_thread_registration_failure();
  if (ml_fuse_mark_ocaml_thread() != 0) {
    status = ML_FUSE_MAIN_THREAD_REGISTRATION;
    goto out_unmount;
  }

  caml_release_runtime_system();
  if (loop_mode == ML_FUSE_LOOP_MULTI_THREADED)
    loop_result = fuse_loop_mt(fuse, opts.clone_fd);
  else
    loop_result = fuse_loop(fuse);
  caml_acquire_runtime_system();
  ml_fuse_clear_thread_kind();

  if (loop_result != 0)
    status = ML_FUSE_MAIN_LOOP;
  else if (ml_fuse_thread_registration_has_failed())
    status = ML_FUSE_MAIN_THREAD_REGISTRATION;

out_unmount:
  if (signal_handlers_set)
    fuse_remove_signal_handlers(session);
  if (mounted)
    fuse_unmount(fuse);

out_destroy:
  if (fuse != NULL)
    fuse_destroy(fuse);

out_opts:
  free(opts.mountpoint);

out_args:
  fuse_opt_free_args(&args);
  return status;
}
