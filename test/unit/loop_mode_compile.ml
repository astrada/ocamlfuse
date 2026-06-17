let _ : string array -> Fuse.operations -> unit = Fuse.main

let _ : string array -> Fuse.operations -> unit =
  Fuse.main ~loop_mode:Fuse.Single_threaded

let _ : string array -> Fuse.operations -> unit =
  Fuse.main ~loop_mode:Fuse.Multi_threaded

let _ : string array -> Fuse.Fuse_compat.operations -> unit =
  Fuse.Fuse_compat.main

let _ : string array -> Fuse.Fuse_compat.operations -> unit =
  Fuse.Fuse_compat.main ~loop_mode:Fuse.Single_threaded

let _ : string array -> Fuse.Fuse_compat.operations -> unit =
  Fuse.Fuse_compat.main ~loop_mode:Fuse.Multi_threaded
