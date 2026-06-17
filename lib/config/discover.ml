module C = Configurator.V1

let read_file path =
  let in_ch = open_in path in
  let rec loop acc =
    try
      let line = input_line in_ch in
      loop (acc ^ line)
    with End_of_file -> acc
  in
  try
    let result = loop "" in
    close_in in_ch;
    result
  with exc ->
    close_in in_ch;
    Printf.eprintf "read_file: could not read file: '%s'" path;
    raise exc

let () =
  C.main ~name:"fuse3" (fun c ->
      let conf =
        match C.Pkg_config.get c with
        | None -> C.die "pkg-config is required to find libfuse3"
        | Some pkgc -> (
            match
              C.Pkg_config.query_expr_err pkgc ~package:"fuse3"
                ~expr:"fuse3 >= 3.10.0"
            with
            | Ok flags -> flags
            | Error msg ->
                C.die "could not find libfuse3 >= 3.10.0 with pkg-config: %s"
                  msg)
      in
      let calmidl_fname = "camlidl.libs.sexp" in
      let camlidl_lib_path =
        match
          Sys.command (Printf.sprintf "opam var camlidl:lib > %s" calmidl_fname)
        with
        | 0 -> String.trim (read_file calmidl_fname)
        | _ -> (
            match
              Sys.command
                (Printf.sprintf "ocamlfind query camlidl > %s" calmidl_fname)
            with
            | 0 -> String.trim (read_file calmidl_fname)
            | _ -> C.die "Could not query camlidl lib path")
      in
      let camlidl_libs = [ "-L" ^ camlidl_lib_path; "-lcamlidl" ] in
      C.Flags.(
        write_sexp calmidl_fname camlidl_libs;
        write_sexp "fuse3.cflags.sexp" conf.cflags;
        write_sexp "fuse3.libs.sexp" conf.libs))
