open! Stdune
module C = Configurator.V1

let () =
  C.main ~name:"foo" (fun c ->
      let default : C.Pkg_config.package_conf =
        {libs= ["-lfuse"]; cflags= []}
      in
      let conf =
        match C.Pkg_config.get c with
        | Some pkgc -> (
            match C.Pkg_config.query pkgc ~package:"fuse" with
            | Some flags -> flags
            | None -> default )
        | None -> default
      in
      let calmidl_fname = "camlidl.libs.sexp" in
      let camlidl_lib_path =
        match
          Sys.command
            (Printf.sprintf "opam config var camlidl:lib > %s" calmidl_fname)
        with
        | 0 ->
          String.trim (Io.String_path.read_file calmidl_fname)
        | _ ->
          begin match
              Sys.command
                (Printf.sprintf "ocamlfind query camlidl > %s" calmidl_fname)
            with
            | 0 ->
              String.trim (Io.String_path.read_file calmidl_fname)
            | _ ->
              C.die "Could not query camlidl lib path"
          end
      in
      let camlidl_libs = ["-L" ^ camlidl_lib_path; "-lcamlidl"] in
      C.Flags.(
        write_sexp calmidl_fname camlidl_libs ;
        write_sexp "fuse.cflags.sexp" conf.cflags ;
        write_sexp "fuse.libs.sexp" conf.libs)
    )
