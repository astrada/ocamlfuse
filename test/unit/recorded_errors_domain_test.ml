exception Domain_recorded of int

let fail format = Printf.ksprintf failwith format

let validate_snapshot errors =
  if Array.length errors > 1024 then
    fail "snapshot contains %d entries" (Array.length errors);
  Array.iteri
    (fun index entry ->
      if index > 0 && errors.(index - 1).Fuse.ticket >= entry.Fuse.ticket then
        fail "tickets are not increasing at index %d" index;
      if entry.Fuse.op <> "test" then
        fail "operation %S, expected test" entry.Fuse.op;
      if not (String.starts_with ~prefix:"/domain/" entry.Fuse.path) then
        fail "invalid path %S" entry.Fuse.path;
      match entry.Fuse.exn with
      | Domain_recorded _ -> ()
      | exn -> fail "unexpected exception: %s" (Printexc.to_string exn))
    errors

let () =
  let writer_count = 4 in
  let records_per_writer = 2000 in
  let writers_finished = Atomic.make 0 in
  let writers =
    Array.init writer_count (fun writer ->
        Domain.spawn (fun () ->
            Fun.protect
              ~finally:(fun () ->
                ignore (Atomic.fetch_and_add writers_finished 1))
              (fun () ->
                for index = 0 to records_per_writer - 1 do
                  let number = (writer * records_per_writer) + index in
                  Recorded_errors_test_support.record (Domain_recorded number)
                    (Printf.sprintf "/domain/%d/%d" writer index)
                done)))
  in
  let reader =
    Domain.spawn (fun () ->
        while Atomic.get writers_finished < writer_count do
          validate_snapshot (Fuse.recent_errors ());
          ignore (Fuse.error_count ())
        done)
  in
  let toggler =
    Domain.spawn (fun () ->
        let enabled = ref false in
        while Atomic.get writers_finished < writer_count do
          enabled := not !enabled;
          Fuse.set_backtrace_capture !enabled
        done)
  in
  Domain.join toggler;
  Domain.join reader;
  Array.iter Domain.join writers;
  Fuse.set_backtrace_capture false;
  let expected_count = writer_count * records_per_writer in
  if Fuse.error_count () <> expected_count then
    fail "error_count returned %d, expected %d" (Fuse.error_count ())
      expected_count;
  let errors = Fuse.recent_errors () in
  validate_snapshot errors;
  if Array.length errors <> 1024 then
    fail "final snapshot contains %d entries, expected 1024"
      (Array.length errors)
