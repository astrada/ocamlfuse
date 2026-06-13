open Fuse.Fuse_compat

let _ops : operations =
  {
    default_operations with
    init = (fun () -> ());
    getattr = Unix.LargeFile.lstat;
  }

let _main = main
