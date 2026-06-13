(*
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
*)

module Unix_util = Unix_util
module Fuse_bindings = Fuse_bindings
module Fuse_lib = Fuse_lib
module Fuse_result = Fuse_result

type buffer =
  (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

type context = Fuse_bindings.__fuse_context

val get_context : unit -> context

type xattr_flags = AUTO | CREATE | REPLACE
type file_handle = int64

type file_info = {
  fi_flags : Unix.open_flag list;
  fi_flags_raw : int;
  fi_fh : file_handle;
  fi_writepage : bool;
  fi_direct_io : bool;
  fi_keep_cache : bool;
  fi_flush : bool;
  fi_nonseekable : bool;
  fi_flock_release : bool;
  fi_cache_readdir : bool;
  fi_noflush : bool;
  fi_lock_owner : int64;
  fi_poll_events : int32;
}

type file_info_update = {
  fi_update_fh : file_handle option;
  fi_update_direct_io : bool;
  fi_update_keep_cache : bool;
  fi_update_nonseekable : bool;
  fi_update_cache_readdir : bool;
  fi_update_noflush : bool;
}

val default_file_info_update : file_info_update

type rename_flags = {
  rename_noreplace : bool;
  rename_exchange : bool;
  rename_whiteout : bool;
  rename_flags_raw : int;
}

type readdir_flags = { readdir_plus : bool; readdir_flags_raw : int }
type fill_dir_flags = { fill_dir_plus : bool }

type dir_entry = {
  entry_name : string;
  entry_stats : Unix.LargeFile.stats option;
  entry_offset : int64 option;
  entry_flags : fill_dir_flags;
}

type timespec = { tv_sec : int64; tv_nsec : int }
type timestamp = Time of timespec | Now | Omit

type operations = {
  init : unit -> unit;
  getattr : string -> file_info option -> Unix.LargeFile.stats;
  readlink : string -> string;
  mknod : string -> int -> unit;
  mkdir : string -> int -> unit;
  unlink : string -> unit;
  rmdir : string -> unit;
  symlink : string -> string -> unit;
  rename : string -> string -> rename_flags -> unit;
  link : string -> string -> unit;
  chmod : string -> int -> file_info option -> unit;
  chown : string -> int -> int -> file_info option -> unit;
  truncate : string -> int64 -> file_info option -> unit;
  utimens : string -> timestamp -> timestamp -> file_info option -> unit;
  fopen : string -> file_info -> file_info_update;
  read : string -> buffer -> int64 -> file_info -> int;
  write : string -> buffer -> int64 -> file_info -> int;
  statfs : string -> Unix_util.statvfs;
  flush : string -> file_info -> unit;
  release : string -> file_info -> unit;
  fsync : string -> bool -> file_info -> unit;
  setxattr : string -> string -> string -> xattr_flags -> unit;
  getxattr : string -> string -> string;
  listxattr : string -> string list;
  removexattr : string -> string -> unit;
  opendir : string -> file_info -> file_info_update;
  readdir : string -> int64 -> file_info -> readdir_flags -> dir_entry list;
  releasedir : string -> file_info -> unit;
  fsyncdir : string -> bool -> file_info -> unit;
      (* TODO: missing callbacks:

         destroy, access, create, lock, bmap, flag_nullpath_ok, ioctl, poll *)
}

val op_names_of_operations : operations -> Fuse_bindings.fuse_operation_names
val default_operations : operations
val main : Fuse_bindings.str array -> operations -> unit

module Fuse_compat : sig
  type operations = {
    getattr : string -> Unix.LargeFile.stats;
    readlink : string -> string;
    mknod : string -> int -> unit;
    mkdir : string -> int -> unit;
    unlink : string -> unit;
    rmdir : string -> unit;
    symlink : string -> string -> unit;
    rename : string -> string -> unit;
    link : string -> string -> unit;
    chmod : string -> int -> unit;
    chown : string -> int -> int -> unit;
    truncate : string -> int64 -> unit;
    utime : string -> float -> float -> unit;
    fopen : string -> Unix.open_flag list -> int option;
    read : string -> buffer -> int64 -> int -> int;
    write : string -> buffer -> int64 -> int -> int;
    statfs : string -> Unix_util.statvfs;
    flush : string -> int -> unit;
    release : string -> Unix.open_flag list -> int -> unit;
    fsync : string -> bool -> int -> unit;
    setxattr : string -> string -> string -> xattr_flags -> unit;
    getxattr : string -> string -> string;
    listxattr : string -> string list;
    removexattr : string -> string -> unit;
    opendir : string -> Unix.open_flag list -> int option;
    readdir : string -> int -> string list;
    releasedir : string -> Unix.open_flag list -> int -> unit;
    fsyncdir : string -> bool -> int -> unit;
    init : unit -> unit;
  }

  val default_operations : operations
  val main : Fuse_bindings.str array -> operations -> unit
end
