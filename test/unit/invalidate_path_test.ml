let _ : string -> unit = Fuse.invalidate_path

let invalidation_error path =
  try
    Fuse.invalidate_path path;
    failwith "invalidate_path unexpectedly succeeded without a live mount"
  with
  | Unix.Unix_error (Unix.EUNKNOWNERR errno, "invalidate_path", error_path)
    when error_path = path ->
      errno
  | exn ->
      failwith
        ("invalidate_path raised an unexpected exception: "
       ^ Printexc.to_string exn)

let () =
  let no_mount_errno = invalidation_error "/" in
  let long_path = "/" ^ String.make 65_536 'a' in
  let long_path_errno = invalidation_error long_path in
  if long_path_errno <> no_mount_errno then
    failwith "a long path did not reach the normal no-mount check";
  let null_path_errno = invalidation_error "/valid\x00truncated" in
  if null_path_errno = no_mount_errno then
    failwith "a path containing a null byte was not rejected before lookup"
