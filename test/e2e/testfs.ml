open Unix
open Fuse
open Fuse.Fuse_compat

let getenv_required name =
  try Sys.getenv name
  with Not_found -> failwith ("missing required environment variable: " ^ name)

let backing_root = getenv_required "OCAMLFUSE_E2E_BACKING_ROOT"
let log_path = getenv_required "OCAMLFUSE_E2E_LOG"
let ready_path = getenv_required "OCAMLFUSE_E2E_READY"
let raise_unix err fn path = raise (Unix_error (err, fn, path))

let components path =
  let add_component path start stop acc =
    if stop <= start then acc
    else
      let component = String.sub path start (stop - start) in
      if component = "." || component = ".." then
        raise_unix EACCES "resolve" path
      else component :: acc
  in
  let len = String.length path in
  let rec loop i start acc =
    if i = len then List.rev (add_component path start i acc)
    else if path.[i] = '/' then
      loop (i + 1) (i + 1) (add_component path start i acc)
    else loop (i + 1) start acc
  in
  loop 0 0 []

let real_path path =
  List.fold_left Filename.concat backing_root (components path)

let log_mutex = Mutex.create ()

let with_mutex mutex f =
  Mutex.lock mutex;
  try
    let result = f () in
    Mutex.unlock mutex;
    result
  with exn ->
    Mutex.unlock mutex;
    raise exn

let log event =
  with_mutex log_mutex (fun () ->
      let channel =
        open_out_gen [ Open_creat; Open_append; Open_text ] 0o644 log_path
      in
      try
        output_string channel event;
        output_char channel '\n';
        close_out channel
      with exn ->
        close_out_noerr channel;
        raise exn)

let store_descr fd = Unix_util.int_of_file_descr fd
let retrieve_descr fd = Unix_util.file_descr_of_int fd
let file_mode mode = mode land 0o7777
let flags_or_readonly flags = match flags with [] -> [ O_RDONLY ] | _ -> flags
let xattrs = Hashtbl.create 64
let xattr_mutex = Mutex.create ()
let ensure_exists _fn path = ignore (Unix.LargeFile.lstat (real_path path))

let attrs_for path =
  let key = real_path path in
  try Hashtbl.find xattrs key
  with Not_found ->
    let attrs = Hashtbl.create 4 in
    Hashtbl.add xattrs key attrs;
    attrs

let missing_xattr fn path = raise (Unix_error (EUNKNOWNERR 61, fn, path))
let list_keys table = Hashtbl.fold (fun key _value keys -> key :: keys) table []

let test_operations =
  {
    init =
      (fun () ->
        log "init";
        let channel = open_out ready_path in
        output_string channel "ready\n";
        close_out channel);
    getattr =
      (fun path ->
        log "getattr";
        Unix.LargeFile.lstat (real_path path));
    readlink =
      (fun path ->
        log "readlink";
        Unix.readlink (real_path path));
    mknod =
      (fun path mode ->
        log "mknod";
        let fd =
          Unix.openfile (real_path path)
            [ O_CREAT; O_EXCL; O_WRONLY ]
            (file_mode mode)
        in
        Unix.close fd);
    mkdir =
      (fun path mode ->
        log "mkdir";
        Unix.mkdir (real_path path) (file_mode mode));
    unlink =
      (fun path ->
        log "unlink";
        Unix.unlink (real_path path));
    rmdir =
      (fun path ->
        log "rmdir";
        Unix.rmdir (real_path path));
    symlink =
      (fun target link_path ->
        log "symlink";
        Unix.symlink target (real_path link_path));
    rename =
      (fun old_path new_path ->
        log "rename";
        Unix.rename (real_path old_path) (real_path new_path));
    link =
      (fun old_path new_path ->
        log "link";
        Unix.link (real_path old_path) (real_path new_path));
    chmod =
      (fun path mode ->
        log "chmod";
        Unix.chmod (real_path path) (file_mode mode));
    chown =
      (fun path uid gid ->
        log "chown";
        Unix.chown (real_path path) uid gid);
    truncate =
      (fun path size ->
        log "truncate";
        Unix.LargeFile.truncate (real_path path) size);
    utime =
      (fun path atime mtime ->
        log "utime";
        Unix.utimes (real_path path) atime mtime);
    fopen =
      (fun path flags ->
        log "fopen";
        let fd =
          Unix.openfile (real_path path) (flags_or_readonly flags) 0o666
        in
        Some (store_descr fd));
    read =
      (fun _path buf offset fd ->
        log "read";
        let file_descr = retrieve_descr fd in
        ignore (Unix.LargeFile.lseek file_descr offset SEEK_SET);
        Unix_util.read file_descr buf);
    write =
      (fun _path buf offset fd ->
        log "write";
        let file_descr = retrieve_descr fd in
        ignore (Unix.LargeFile.lseek file_descr offset SEEK_SET);
        Unix_util.write file_descr buf);
    statfs =
      (fun path ->
        log "statfs";
        Unix_util.statvfs (real_path path));
    flush =
      (fun _path _fd ->
        log "flush";
        ());
    release =
      (fun _path _flags fd ->
        log "release";
        Unix.close (retrieve_descr fd));
    fsync =
      (fun _path _isdatasync fd ->
        log "fsync";
        Unix.fsync (retrieve_descr fd));
    setxattr =
      (fun path attr value flag ->
        log "setxattr";
        ensure_exists "setxattr" path;
        with_mutex xattr_mutex (fun () ->
            let attrs = attrs_for path in
            let exists = Hashtbl.mem attrs attr in
            match (flag, exists) with
            | CREATE, true -> raise_unix EEXIST "setxattr" path
            | REPLACE, false -> missing_xattr "setxattr" path
            | AUTO, _ | CREATE, false | REPLACE, true ->
                Hashtbl.replace attrs attr value));
    getxattr =
      (fun path attr ->
        log "getxattr";
        ensure_exists "getxattr" path;
        with_mutex xattr_mutex (fun () ->
            try Hashtbl.find (attrs_for path) attr
            with Not_found -> missing_xattr "getxattr" path));
    listxattr =
      (fun path ->
        log "listxattr";
        ensure_exists "listxattr" path;
        with_mutex xattr_mutex (fun () -> list_keys (attrs_for path)));
    removexattr =
      (fun path attr ->
        log "removexattr";
        ensure_exists "removexattr" path;
        with_mutex xattr_mutex (fun () ->
            let attrs = attrs_for path in
            if Hashtbl.mem attrs attr then Hashtbl.remove attrs attr
            else missing_xattr "removexattr" path));
    opendir =
      (fun path flags ->
        log "opendir";
        let fd = Unix.openfile (real_path path) (flags_or_readonly flags) 0 in
        Some (store_descr fd));
    readdir =
      (fun path _fd ->
        log "readdir";
        "." :: ".." :: Array.to_list (Sys.readdir (real_path path)));
    releasedir =
      (fun _path _flags fd ->
        log "releasedir";
        Unix.close (retrieve_descr fd));
    fsyncdir =
      (fun _path _isdatasync fd ->
        log "fsyncdir";
        Unix.fsync (retrieve_descr fd));
  }

let () = main Sys.argv test_operations
