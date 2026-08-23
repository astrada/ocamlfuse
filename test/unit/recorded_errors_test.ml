let fail format = Printf.ksprintf failwith format

let () =
  let errors = Fuse.recent_errors () in
  if Array.length errors <> 0 then
    fail "recent_errors returned %d entries before Fuse.main"
      (Array.length errors);
  if Fuse.error_count () <> 0 then
    fail "error_count returned %d before Fuse.main" (Fuse.error_count ());
  Fuse.set_backtrace_capture true;
  Gc.full_major ();
  if Array.length (Fuse.recent_errors ()) <> 0 then
    failwith "a collection made the empty error ring nonempty";
  Fuse.set_backtrace_capture false
