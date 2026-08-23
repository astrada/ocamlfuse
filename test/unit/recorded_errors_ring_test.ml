exception Recorded of int

let fail format = Printf.ksprintf failwith format

let entry_number entry =
  match entry.Fuse.exn with
  | Recorded number -> number
  | exn -> fail "unexpected recorded exception: %s" (Printexc.to_string exn)

let check_entry expected_ticket entry =
  if entry.Fuse.ticket <> expected_ticket then
    fail "ticket %d, expected %d" entry.Fuse.ticket expected_ticket;
  if entry.Fuse.op <> "test" then
    fail "operation %S, expected test" entry.Fuse.op;
  let expected_path = Printf.sprintf "/recorded/%d" expected_ticket in
  if entry.Fuse.path <> expected_path then
    fail "path %S, expected %S" entry.Fuse.path expected_path;
  if entry_number entry <> expected_ticket then
    fail "exception payload did not match ticket %d" expected_ticket;
  match entry.Fuse.backtrace with
  | None -> ()
  | Some _ -> fail "ticket %d unexpectedly has a backtrace" expected_ticket

let () =
  if Fuse.error_count () <> 0 || Array.length (Fuse.recent_errors ()) <> 0 then
    failwith "the process-lifetime ring did not start empty";
  let total = 2049 in
  for ticket = 0 to total - 1 do
    Recorded_errors_test_support.record (Recorded ticket)
      (Printf.sprintf "/recorded/%d" ticket)
  done;
  if Fuse.error_count () <> total then
    fail "error_count returned %d, expected %d" (Fuse.error_count ()) total;
  let errors = Fuse.recent_errors () in
  if Array.length errors <> 1024 then
    fail "ring retained %d entries, expected 1024" (Array.length errors);
  let first_ticket = total - Array.length errors in
  Array.iteri
    (fun index entry -> check_entry (first_ticket + index) entry)
    errors;

  for _ = 1 to 2 do
    Fuse.main [| Sys.argv.(0); "--version" |] Fuse.default_operations
  done;
  if Fuse.error_count () <> total then
    fail "repeated Fuse.main calls reset error_count to %d"
      (Fuse.error_count ());
  let after_main = Fuse.recent_errors () in
  if
    Array.length after_main <> 1024
    || after_main.(0).Fuse.ticket <> first_ticket
    || after_main.(1023).Fuse.ticket <> total - 1
  then failwith "repeated Fuse.main calls reset the recorded-error ring";

  Fuse.set_backtrace_capture true;
  Callback.register "ml_fuse_capture_backtrace" (fun () -> raise Out_of_memory);
  Recorded_errors_test_support.record (Recorded total) "/capture-failure";
  let errors = Fuse.recent_errors () in
  let last = errors.(Array.length errors - 1) in
  if last.Fuse.ticket <> total then
    fail "capture-failure ticket %d, expected %d" last.Fuse.ticket total;
  if last.Fuse.path <> "/capture-failure" then
    fail "capture-failure path is %S" last.Fuse.path;
  if entry_number last <> total then
    failwith "capture failure replaced the original exception";
  (match last.Fuse.backtrace with
  | None -> ()
  | Some _ -> failwith "a failed capture retained a backtrace");
  if Fuse.error_count () <> total + 1 then
    fail "capture failure left error_count at %d" (Fuse.error_count ())
