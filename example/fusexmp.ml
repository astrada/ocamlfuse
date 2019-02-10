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

let store_descr fd = Unix_util.int_of_file_descr fd

(* this can be an hashtable in more complicated cases *)
let retrieve_descr i = Unix_util.file_descr_of_int i

let xmp_read _path buf offset d =
  let hnd = retrieve_descr d in
  ignore (LargeFile.lseek hnd offset SEEK_SET) ;
  Unix_util.read hnd buf

let xmp_write _path buf offset d =
  let hnd = retrieve_descr d in
  ignore (LargeFile.lseek hnd offset SEEK_SET) ;
  Unix_util.write hnd buf

(* Extended attributes helpers *)

let xattr = Hashtbl.create 256

let xattr_lock = Mutex.create ()

let with_xattr_lock f x =
  Mutex.lock xattr_lock ;
  let v = try f x with e -> Mutex.unlock xattr_lock ; raise e in
  Mutex.unlock xattr_lock ; v

let lskeys t = with_xattr_lock (Hashtbl.fold (fun k _v l -> k :: l) t) []

let init_attr xattr path =
  if not (Hashtbl.mem xattr path) then
    Hashtbl.add xattr path (Hashtbl.create 256)

(* call to Fuse.main and creation of the filesystem *)

let _ =
  main Sys.argv
    { init= (fun () -> Printf.printf "filesystem started\n%!")
    ; statfs= Unix_util.statvfs
    ; getattr= Unix.LargeFile.lstat
    ; readdir=
        (fun path _hnd -> "." :: ".." :: Array.to_list (Sys.readdir path))
    ; opendir=
        (fun path flags ->
          Unix.close (Unix.openfile path flags 0) ;
          None )
    ; releasedir= (fun _path _mode _hnd -> ())
    ; fsyncdir= (fun _path _ds _hnd -> Printf.printf "sync dir\n%!")
    ; readlink= Unix.readlink
    ; utime= Unix.utimes
    ; fopen= (fun path flags -> Some (store_descr (Unix.openfile path flags 0)))
    ; read= xmp_read
    ; write= xmp_write
    ; mknod= (fun path mode -> close (openfile path [O_CREAT; O_EXCL] mode))
    ; mkdir= Unix.mkdir
    ; unlink= Unix.unlink
    ; rmdir= Unix.rmdir
    ; symlink= Unix.symlink
    ; rename= Unix.rename
    ; link= Unix.link
    ; chmod= Unix.chmod
    ; chown= Unix.chown
    ; truncate= Unix.LargeFile.truncate
    ; release= (fun _path _mode hnd -> Unix.close (retrieve_descr hnd))
    ; flush= (fun _path _hnd -> ())
    ; fsync= (fun _path _ds _hnd -> Printf.printf "sync\n%!")
    ; listxattr=
        (fun path ->
          init_attr xattr path ;
          lskeys (Hashtbl.find xattr path) )
    ; getxattr=
        (fun path attr ->
          with_xattr_lock
            (fun () ->
              init_attr xattr path ;
              try Hashtbl.find (Hashtbl.find xattr path) attr
              with Not_found ->
                raise
                  (Unix.Unix_error
                     ( EUNKNOWNERR 61 (* TODO: this is system-dependent *)
                     , "getxattr"
                     , path )) )
            () )
    ; setxattr=
        (fun path attr value _flag ->
          (* TODO: This currently ignores flags *)
          with_xattr_lock
            (fun () ->
              init_attr xattr path ;
              Hashtbl.replace (Hashtbl.find xattr path) attr value )
            () )
    ; removexattr=
        (fun path attr ->
          with_xattr_lock
            (fun () ->
              init_attr xattr path ;
              Hashtbl.remove (Hashtbl.find xattr path) attr )
            () ) }
