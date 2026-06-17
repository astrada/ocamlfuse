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

open Fuse_lib
module Unix_util = Unix_util
module Fuse_bindings = Fuse_bindings
module Fuse_lib = Fuse_lib
module Fuse_result = Fuse_result

type buffer =
  (char, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

type context = Fuse_bindings.__fuse_context

let get_context : unit -> context = Fuse_bindings.fuse_get_context

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
  fi_lock_owner : int64;
  fi_poll_events : int32;
}

type file_info_update = {
  fi_update_fh : file_handle option;
  fi_update_direct_io : bool;
  fi_update_keep_cache : bool;
  fi_update_nonseekable : bool;
  fi_update_cache_readdir : bool;
}

let default_file_info_update =
  {
    fi_update_fh = None;
    fi_update_direct_io = false;
    fi_update_keep_cache = false;
    fi_update_nonseekable = false;
    fi_update_cache_readdir = false;
  }

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
type loop_mode = Single_threaded | Multi_threaded

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
}

let op_names_of_operations ops =
  {
    Fuse_bindings.init = Fuse_lib.named_op ops.init;
    Fuse_bindings.getattr = Fuse_lib.named_op_2 ops.getattr;
    Fuse_bindings.readlink = Fuse_lib.named_op ops.readlink;
    Fuse_bindings.readdir = Fuse_lib.named_op_4 ops.readdir;
    Fuse_bindings.opendir = Fuse_lib.named_op_2 ops.opendir;
    Fuse_bindings.releasedir = Fuse_lib.named_op_2 ops.releasedir;
    Fuse_bindings.fsyncdir = Fuse_lib.named_op_3 ops.fsyncdir;
    Fuse_bindings.mknod = Fuse_lib.named_op_2 ops.mknod;
    Fuse_bindings.mkdir = Fuse_lib.named_op_2 ops.mkdir;
    Fuse_bindings.unlink = Fuse_lib.named_op ops.unlink;
    Fuse_bindings.rmdir = Fuse_lib.named_op ops.rmdir;
    Fuse_bindings.symlink = Fuse_lib.named_op_2 ops.symlink;
    Fuse_bindings.rename = Fuse_lib.named_op_3 ops.rename;
    Fuse_bindings.link = Fuse_lib.named_op_2 ops.link;
    Fuse_bindings.chmod = Fuse_lib.named_op_3 ops.chmod;
    Fuse_bindings.chown = Fuse_lib.named_op_4 ops.chown;
    Fuse_bindings.truncate = Fuse_lib.named_op_3 ops.truncate;
    Fuse_bindings.utimens = Fuse_lib.named_op_4 ops.utimens;
    Fuse_bindings.fopen = Fuse_lib.named_op_2 ops.fopen;
    Fuse_bindings.read = Fuse_lib.named_op_4 ops.read;
    Fuse_bindings.write = Fuse_lib.named_op_4 ops.write;
    Fuse_bindings.release = Fuse_lib.named_op_2 ops.release;
    Fuse_bindings.flush = Fuse_lib.named_op_2 ops.flush;
    Fuse_bindings.statfs = Fuse_lib.named_op ops.statfs;
    Fuse_bindings.fsync = Fuse_lib.named_op_3 ops.fsync;
    Fuse_bindings.listxattr =
      Fuse_lib.named_op (fun path ->
          let s = ops.listxattr path in
          (s, List.fold_left (fun acc s -> acc + 1 + String.length s) 0 s));
    Fuse_bindings.getxattr = Fuse_lib.named_op_2 ops.getxattr;
    Fuse_bindings.setxattr = Fuse_lib.named_op_4 ops.setxattr;
    Fuse_bindings.removexattr = Fuse_lib.named_op_2 ops.removexattr;
  }

let default_operations =
  {
    init = undefined;
    getattr = undefined;
    readdir = undefined;
    opendir = undefined;
    releasedir = undefined;
    fsyncdir = undefined;
    readlink = undefined;
    mknod = undefined;
    mkdir = undefined;
    unlink = undefined;
    rmdir = undefined;
    symlink = undefined;
    rename = undefined;
    link = undefined;
    chmod = undefined;
    chown = undefined;
    truncate = undefined;
    utimens = undefined;
    fopen = undefined;
    read = undefined;
    write = undefined;
    flush = undefined;
    release = undefined;
    statfs = undefined;
    fsync = undefined;
    listxattr = undefined;
    getxattr = undefined;
    setxattr = undefined;
    removexattr = undefined;
  }

let int_of_loop_mode = function Single_threaded -> 0 | Multi_threaded -> 1

let main ?(loop_mode = Multi_threaded) argv ops =
  Fuse_bindings.ml_fuse_init ();
  Fuse_bindings.set_fuse_operations (op_names_of_operations ops);
  let loop_mode = int_of_loop_mode loop_mode in
  match
    Fuse_bindings.ml_fuse_main argv
      (Fuse_bindings.get_fuse_operations ())
      loop_mode
  with
  | 0 -> ()
  | 1 -> failwith "fuse command-line parsing failed"
  | 2 -> failwith "fuse mountpoint was not provided"
  | 3 -> failwith "fuse_new failed"
  | 4 -> failwith "fuse_mount failed"
  | 5 -> failwith "fuse_daemonize failed"
  | 6 -> failwith "fuse_set_signal_handlers failed"
  | 7 -> failwith "fuse_loop failed"
  | 8 -> failwith "fuse worker thread registration failed"
  | status -> failwith ("fuse failed with status " ^ string_of_int status)

let fuse3_main = main

module Fuse_compat = struct
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

  let default_operations =
    {
      init = undefined;
      getattr = undefined;
      readdir = undefined;
      opendir = undefined;
      releasedir = undefined;
      fsyncdir = undefined;
      readlink = undefined;
      mknod = undefined;
      mkdir = undefined;
      unlink = undefined;
      rmdir = undefined;
      symlink = undefined;
      rename = undefined;
      link = undefined;
      chmod = undefined;
      chown = undefined;
      truncate = undefined;
      utime = undefined;
      fopen = undefined;
      read = undefined;
      write = undefined;
      flush = undefined;
      release = undefined;
      statfs = undefined;
      fsync = undefined;
      listxattr = undefined;
      getxattr = undefined;
      setxattr = undefined;
      removexattr = undefined;
    }

  let default_entry_flags = { fill_dir_plus = false }

  let entry_of_name entry_name =
    {
      entry_name;
      entry_stats = None;
      entry_offset = None;
      entry_flags = default_entry_flags;
    }

  let file_info_update_of_handle = function
    | None -> default_file_info_update
    | Some fh ->
        { default_file_info_update with fi_update_fh = Some (Int64.of_int fh) }

  let int_of_file_handle fh =
    let min_fh = Int64.of_int min_int in
    let max_fh = Int64.of_int max_int in
    if Int64.compare fh min_fh < 0 || Int64.compare fh max_fh > 0 then
      raise (Unix.Unix_error (Unix.EOVERFLOW, "file handle", ""))
    else Int64.to_int fh

  let file_handle_as_int fi = int_of_file_handle fi.fi_fh

  let float_of_timestamp fn path = function
    | Time { tv_sec; tv_nsec } ->
        Int64.to_float tv_sec +. (float tv_nsec /. 1_000_000_000.0)
    | Now | Omit -> raise (Unix.Unix_error (Unix.EINVAL, fn, path))

  let main ?loop_mode argv ops =
    fuse3_main ?loop_mode argv
      {
        init = ops.init;
        getattr =
          (if ops.getattr == undefined then undefined
           else fun path _fi -> ops.getattr path);
        readlink = ops.readlink;
        mknod = ops.mknod;
        mkdir = ops.mkdir;
        unlink = ops.unlink;
        rmdir = ops.rmdir;
        symlink = ops.symlink;
        rename =
          (if ops.rename == undefined then undefined
           else fun old_path new_path flags ->
             if flags.rename_flags_raw <> 0 then
               raise (Unix.Unix_error (Unix.EINVAL, "rename", old_path))
             else ops.rename old_path new_path);
        link = ops.link;
        chmod =
          (if ops.chmod == undefined then undefined
           else fun path mode _fi -> ops.chmod path mode);
        chown =
          (if ops.chown == undefined then undefined
           else fun path uid gid _fi -> ops.chown path uid gid);
        truncate =
          (if ops.truncate == undefined then undefined
           else fun path size _fi -> ops.truncate path size);
        utimens =
          (if ops.utime == undefined then undefined
           else fun path atime mtime _fi ->
             ops.utime path
               (float_of_timestamp "utime" path atime)
               (float_of_timestamp "utime" path mtime));
        fopen =
          (if ops.fopen == undefined then undefined
           else fun path fi ->
             file_info_update_of_handle (ops.fopen path fi.fi_flags));
        read =
          (if ops.read == undefined then undefined
           else fun path buf offset fi ->
             ops.read path buf offset (file_handle_as_int fi));
        write =
          (if ops.write == undefined then undefined
           else fun path buf offset fi ->
             ops.write path buf offset (file_handle_as_int fi));
        statfs = ops.statfs;
        flush =
          (if ops.flush == undefined then undefined
           else fun path fi -> ops.flush path (file_handle_as_int fi));
        release =
          (if ops.release == undefined then undefined
           else fun path fi ->
             ops.release path fi.fi_flags (file_handle_as_int fi));
        fsync =
          (if ops.fsync == undefined then undefined
           else fun path datasync fi ->
             ops.fsync path datasync (file_handle_as_int fi));
        setxattr = ops.setxattr;
        getxattr = ops.getxattr;
        listxattr = ops.listxattr;
        removexattr = ops.removexattr;
        opendir =
          (if ops.opendir == undefined then undefined
           else fun path fi ->
             file_info_update_of_handle (ops.opendir path fi.fi_flags));
        readdir =
          (if ops.readdir == undefined then undefined
           else fun path _offset fi _flags ->
             List.map entry_of_name (ops.readdir path (file_handle_as_int fi)));
        releasedir =
          (if ops.releasedir == undefined then undefined
           else fun path fi ->
             ops.releasedir path fi.fi_flags (file_handle_as_int fi));
        fsyncdir =
          (if ops.fsyncdir == undefined then undefined
           else fun path datasync fi ->
             ops.fsyncdir path datasync (file_handle_as_int fi));
      }
end
