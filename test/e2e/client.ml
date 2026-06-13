open OUnit2

let getenv_required name =
  try Sys.getenv name
  with Not_found -> failwith ("missing required environment variable: " ^ name)

let mode = try Sys.getenv "OCAMLFUSE_E2E_MODE" with Not_found -> "smoke"
let mountpoint = getenv_required "OCAMLFUSE_E2E_MOUNTPOINT"
let log_path = getenv_required "OCAMLFUSE_E2E_LOG"
let prefix = Printf.sprintf "ocamlfuse_e2e_%d" (Unix.getpid ())

external setxattr : string -> string -> string -> unit
  = "ocamlfuse_e2e_setxattr"

external getxattr : string -> string -> string = "ocamlfuse_e2e_getxattr"
external listxattr : string -> string list = "ocamlfuse_e2e_listxattr"
external removexattr : string -> string -> unit = "ocamlfuse_e2e_removexattr"
external utimens_now_omit : string -> unit = "ocamlfuse_e2e_utimens_now_omit"

external rename_noreplace : string -> string -> unit
  = "ocamlfuse_e2e_rename_noreplace"

let path name = Filename.concat mountpoint name

let lines_of_file file =
  let channel = open_in file in
  let rec loop acc =
    try
      let line = input_line channel in
      loop (line :: acc)
    with End_of_file ->
      close_in channel;
      List.rev acc
  in
  try loop []
  with exn ->
    close_in_noerr channel;
    raise exn

let has_event event =
  List.exists (fun line -> line = event) (lines_of_file log_path)

let assert_event event =
  assert_bool ("expected callback event: " ^ event) (has_event event)

let assert_events events = List.iter assert_event events

let write_all fd contents =
  let bytes = Bytes.of_string contents in
  let length = Bytes.length bytes in
  let rec loop offset =
    if offset < length then (
      let written = Unix.write fd bytes offset (length - offset) in
      if written = 0 then failwith "short write to mounted filesystem";
      loop (offset + written))
  in
  loop 0

let with_fd file flags perm f =
  let fd = Unix.openfile file flags perm in
  try
    let result = f fd in
    Unix.close fd;
    result
  with exn ->
    (try Unix.close fd with _ -> ());
    raise exn

let read_file file =
  let channel = open_in_bin file in
  try
    let length = in_channel_length channel in
    let bytes = Bytes.create length in
    really_input channel bytes 0 length;
    close_in channel;
    Bytes.to_string bytes
  with exn ->
    close_in_noerr channel;
    raise exn

let write_file file contents =
  with_fd file [ Unix.O_CREAT; Unix.O_TRUNC; Unix.O_WRONLY ] 0o644 (fun fd ->
      write_all fd contents)

let remove_if_exists file =
  try Unix.unlink file with Unix.Unix_error (Unix.ENOENT, _, _) -> ()

let rmdir_if_exists dir =
  try Unix.rmdir dir with Unix.Unix_error (Unix.ENOENT, _, _) -> ()

let assert_contains value values =
  assert_bool
    (Printf.sprintf "expected %S in list" value)
    (List.exists (fun item -> item = value) values)

let assert_not_contains value values =
  assert_bool
    (Printf.sprintf "did not expect %S in list" value)
    (not (List.exists (fun item -> item = value) values))

let assert_unix_error expected f =
  try
    f ();
    assert_failure
      (Printf.sprintf "expected Unix_error %s" (Unix.error_message expected))
  with Unix.Unix_error (actual, _, _) when actual = expected -> ()

let is_unsupported_dir_fsync = function
  | Unix.Unix_error
      ((Unix.EINVAL | Unix.EBADF | Unix.EISDIR | Unix.EOPNOTSUPP), _, _) ->
      true
  | _ -> false

let is_unsupported_link = function
  | Unix.Unix_error
      ((Unix.EPERM | Unix.EACCES | Unix.EXDEV | Unix.EOPNOTSUPP), _, _) ->
      true
  | _ -> false

let smoke_test _ctxt =
  assert_event "init";
  ignore (Unix.LargeFile.stat mountpoint);
  let file = path (prefix ^ "_smoke.txt") in
  remove_if_exists file;
  write_file file "hello from ocamlfuse\n";
  assert_equal "hello from ocamlfuse\n" (read_file file);
  remove_if_exists file;
  assert_events [ "getattr"; "mknod"; "fopen"; "write"; "read"; "release" ]

let metadata_and_directory_test _ctxt =
  ignore (Unix.LargeFile.stat mountpoint);
  let stats = Fuse.Unix_util.statvfs mountpoint in
  assert_bool "expected positive statfs block size"
    (stats.Fuse.Unix_util.f_bsize > 0L);
  let dir = path (prefix ^ "_dir") in
  rmdir_if_exists dir;
  Unix.mkdir dir 0o755;
  let entries = Array.to_list (Sys.readdir mountpoint) in
  assert_contains (Filename.basename dir) entries;
  Unix.rmdir dir;
  assert_events
    [
      "getattr"; "statfs"; "mkdir"; "opendir"; "readdir"; "releasedir"; "rmdir";
    ]

let file_io_test _ctxt =
  let file = path (prefix ^ "_file.txt") in
  remove_if_exists file;
  with_fd file [ Unix.O_CREAT; Unix.O_EXCL; Unix.O_RDWR ] 0o644 (fun fd ->
      write_all fd "abcdef";
      Unix.fsync fd);
  assert_equal "abcdef" (read_file file);
  remove_if_exists file;
  assert_events
    [ "mknod"; "fopen"; "write"; "fsync"; "flush"; "release"; "read"; "unlink" ]

let resize_permissions_and_times_test _ctxt =
  let file = path (prefix ^ "_attrs.txt") in
  remove_if_exists file;
  write_file file "abcdef";
  Unix.LargeFile.truncate file 3L;
  assert_equal 3L (Unix.LargeFile.stat file).Unix.LargeFile.st_size;
  Unix.LargeFile.truncate file 8L;
  assert_equal 8L (Unix.LargeFile.stat file).Unix.LargeFile.st_size;
  Unix.chmod file 0o600;
  assert_equal ~printer:(Printf.sprintf "%o") 0o600
    ((Unix.LargeFile.stat file).Unix.LargeFile.st_perm land 0o777);
  (try Unix.chown file (Unix.getuid ()) (Unix.getgid ())
   with Unix.Unix_error (Unix.EPERM, _, _) ->
     skip_if true "chown to current uid/gid is not permitted");
  let atime = 1_700_000_001.0 in
  let mtime = 1_700_000_002.0 in
  Unix.utimes file atime mtime;
  let stats = Unix.LargeFile.stat file in
  assert_bool "mtime should be updated"
    (abs_float (stats.Unix.LargeFile.st_mtime -. mtime) < 2.0);
  remove_if_exists file;
  assert_events [ "truncate"; "chmod"; "chown"; "utimens" ]

let utimens_sentinel_test _ctxt =
  let file = path (prefix ^ "_utimens_sentinels.txt") in
  remove_if_exists file;
  write_file file "timestamps";
  let atime = 1_100_000_001.0 in
  let mtime = 1_100_000_002.0 in
  Unix.utimes file atime mtime;
  let before = Unix.LargeFile.stat file in
  utimens_now_omit file;
  let after = Unix.LargeFile.stat file in
  assert_bool "atime should be updated by UTIME_NOW"
    (after.Unix.LargeFile.st_atime > before.Unix.LargeFile.st_atime);
  assert_bool "mtime should be preserved by UTIME_OMIT"
    (abs_float (after.Unix.LargeFile.st_mtime -. before.Unix.LargeFile.st_mtime)
    < 2.0);
  remove_if_exists file;
  assert_event "utimens"

let links_and_rename_test _ctxt =
  let source = path (prefix ^ "_source.txt") in
  let hardlink = path (prefix ^ "_hardlink.txt") in
  let renamed = path (prefix ^ "_renamed.txt") in
  let symlink = path (prefix ^ "_symlink.txt") in
  List.iter remove_if_exists [ source; hardlink; renamed; symlink ];
  write_file source "linked data";
  Unix.symlink (Filename.basename source) symlink;
  assert_equal (Filename.basename source) (Unix.readlink symlink);
  (try Unix.link source hardlink
   with exn ->
     skip_if (is_unsupported_link exn)
       "hard links are not supported by the backing filesystem";
     raise exn);
  assert_equal "linked data" (read_file hardlink);
  Unix.rename source renamed;
  assert_equal "linked data" (read_file renamed);
  List.iter remove_if_exists [ hardlink; renamed; symlink ];
  assert_events [ "symlink"; "readlink"; "link"; "rename"; "unlink" ]

let rename_noreplace_test _ctxt =
  let source = path (prefix ^ "_noreplace_source.txt") in
  let existing = path (prefix ^ "_noreplace_existing.txt") in
  let renamed = path (prefix ^ "_noreplace_renamed.txt") in
  List.iter remove_if_exists [ source; existing; renamed ];
  write_file source "source";
  write_file existing "existing";
  (try
     assert_unix_error Unix.EEXIST (fun () -> rename_noreplace source existing)
   with Unix.Unix_error (Unix.ENOSYS, _, _) ->
     skip_if true "renameat2 is not supported on this kernel");
  assert_equal "source" (read_file source);
  assert_equal "existing" (read_file existing);
  remove_if_exists existing;
  (try rename_noreplace source renamed
   with Unix.Unix_error (Unix.ENOSYS, _, _) ->
     skip_if true "renameat2 is not supported on this kernel");
  assert_equal "source" (read_file renamed);
  remove_if_exists renamed;
  assert_event "rename"

let fsyncdir_test _ctxt =
  let dir = path (prefix ^ "_fsyncdir") in
  rmdir_if_exists dir;
  Unix.mkdir dir 0o755;
  (try
     with_fd dir [ Unix.O_RDONLY ] 0 (fun fd -> Unix.fsync fd);
     assert_event "fsyncdir"
   with exn ->
     skip_if
       (is_unsupported_dir_fsync exn)
       "directory fsync is not supported on this platform";
     raise exn);
  Unix.rmdir dir

let xattr_test _ctxt =
  let file = path (prefix ^ "_xattr.txt") in
  let attr = "user.ocamlfuse_test" in
  remove_if_exists file;
  write_file file "xattr data";
  setxattr file attr "stored value";
  assert_equal "stored value" (getxattr file attr);
  assert_contains attr (listxattr file);
  removexattr file attr;
  assert_not_contains attr (listxattr file);
  remove_if_exists file;
  assert_events [ "setxattr"; "getxattr"; "listxattr"; "removexattr" ]

let full_tests =
  [
    "smoke" >:: smoke_test;
    "metadata-and-directory" >:: metadata_and_directory_test;
    "file-io" >:: file_io_test;
    "resize-permissions-times" >:: resize_permissions_and_times_test;
    "utimens-sentinels" >:: utimens_sentinel_test;
    "links-and-rename" >:: links_and_rename_test;
    "rename-noreplace" >:: rename_noreplace_test;
    "fsyncdir" >:: fsyncdir_test;
    "xattr" >:: xattr_test;
  ]

let smoke_tests = [ "smoke" >:: smoke_test ]

let tests =
  match mode with
  | "smoke" -> smoke_tests
  | "full" -> full_tests
  | other -> failwith ("unknown OCAMLFUSE_E2E_MODE: " ^ other)

let () = run_test_tt_main ("ocamlfuse-e2e" >::: tests)
