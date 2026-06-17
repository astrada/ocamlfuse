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

open Unix
open Fuse

(* Read and write operations a la fuse *)

let store_descr fd = Int64.of_int (Unix_util.int_of_file_descr fd)

(* this can be an hashtable in more complicated cases *)
let retrieve_descr h =
  if h < Int64.of_int min_int || h > Int64.of_int max_int then
    raise (Unix.Unix_error (EOVERFLOW, "file handle", ""))
  else Unix_util.file_descr_of_int (Int64.to_int h)

let file_info_update_of_descr fd =
  { default_file_info_update with fi_update_fh = Some (store_descr fd) }

let xmp_read _path buf offset fi =
  let hnd = retrieve_descr fi.fi_fh in
  ignore (LargeFile.lseek hnd offset SEEK_SET);
  Unix_util.read hnd buf

let xmp_write _path buf offset fi =
  let hnd = retrieve_descr fi.fi_fh in
  ignore (LargeFile.lseek hnd offset SEEK_SET);
  Unix_util.write hnd buf

let timestamp_to_float current = function
  | Time { tv_sec; tv_nsec } ->
      Int64.to_float tv_sec +. (float tv_nsec /. 1_000_000_000.0)
  | Now -> Unix.gettimeofday ()
  | Omit -> current

let default_entry_flags = { fill_dir_plus = false }

let dir_entry entry_name =
  {
    entry_name;
    entry_stats = None;
    entry_offset = None;
    entry_flags = default_entry_flags;
  }

let rename old_path new_path flags =
  match flags.rename_flags_raw with
  | 0 -> Unix.rename old_path new_path
  | 1 when flags.rename_noreplace ->
      if Sys.file_exists new_path then
        raise (Unix.Unix_error (EEXIST, "rename", new_path))
      else Unix.rename old_path new_path
  | _ -> raise (Unix.Unix_error (EINVAL, "rename", old_path))

(* Extended attributes helpers *)

let xattr = Hashtbl.create 256
let xattr_lock = Mutex.create ()

let with_xattr_lock f x =
  Mutex.lock xattr_lock;
  let v =
    try f x
    with e ->
      Mutex.unlock xattr_lock;
      raise e
  in
  Mutex.unlock xattr_lock;
  v

let lskeys t = with_xattr_lock (Hashtbl.fold (fun k _v l -> k :: l) t) []

let init_attr xattr path =
  if not (Hashtbl.mem xattr path) then
    Hashtbl.add xattr path (Hashtbl.create 256)

(* call to Fuse.main and creation of the filesystem *)

let _ =
  main Sys.argv
    {
      init = (fun () -> Printf.printf "filesystem started\n%!");
      statfs = Unix_util.statvfs;
      getattr = (fun path _fi -> Unix.LargeFile.lstat path);
      readdir =
        (fun path _offset _fi _flags ->
          List.map dir_entry ("." :: ".." :: Array.to_list (Sys.readdir path)));
      opendir =
        (fun path fi ->
          file_info_update_of_descr (Unix.openfile path fi.fi_flags 0));
      releasedir = (fun _path fi -> Unix.close (retrieve_descr fi.fi_fh));
      fsyncdir =
        (fun _path _ds fi ->
          Unix.fsync (retrieve_descr fi.fi_fh);
          Printf.printf "sync dir\n%!");
      readlink = Unix.readlink;
      utimens =
        (fun path atime mtime _fi ->
          let stats = Unix.LargeFile.lstat path in
          Unix.utimes path
            (timestamp_to_float stats.st_atime atime)
            (timestamp_to_float stats.st_mtime mtime));
      fopen =
        (fun path fi ->
          file_info_update_of_descr (Unix.openfile path fi.fi_flags 0));
      read = xmp_read;
      write = xmp_write;
      mknod = (fun path mode -> close (openfile path [ O_CREAT; O_EXCL ] mode));
      mkdir = Unix.mkdir;
      unlink = Unix.unlink;
      rmdir = Unix.rmdir;
      symlink = Unix.symlink;
      rename;
      link = Unix.link;
      chmod = (fun path mode _fi -> Unix.chmod path mode);
      chown = (fun path uid gid _fi -> Unix.chown path uid gid);
      truncate = (fun path size _fi -> Unix.LargeFile.truncate path size);
      release = (fun _path fi -> Unix.close (retrieve_descr fi.fi_fh));
      flush = (fun _path _fi -> ());
      fsync =
        (fun _path _ds fi ->
          Unix.fsync (retrieve_descr fi.fi_fh);
          Printf.printf "sync\n%!");
      listxattr =
        (fun path ->
          init_attr xattr path;
          lskeys (Hashtbl.find xattr path));
      getxattr =
        (fun path attr ->
          with_xattr_lock
            (fun () ->
              init_attr xattr path;
              try Hashtbl.find (Hashtbl.find xattr path) attr
              with Not_found ->
                raise
                  (Unix.Unix_error
                     ( EUNKNOWNERR 61 (* TODO: this is system-dependent *),
                       "getxattr",
                       path )))
            ());
      setxattr =
        (fun path attr value _flag ->
          (* TODO: This currently ignores flags *)
          with_xattr_lock
            (fun () ->
              init_attr xattr path;
              Hashtbl.replace (Hashtbl.find xattr path) attr value)
            ());
      removexattr =
        (fun path attr ->
          with_xattr_lock
            (fun () ->
              init_attr xattr path;
              Hashtbl.remove (Hashtbl.find xattr path) attr)
            ());
    }
