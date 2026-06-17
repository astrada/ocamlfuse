# M2 Plan: FUSE 3 Lifecycle Skeleton

Status: complete.

Depends on M1, which is complete.

## Goal

Replace the removed libfuse 2 command-loop integration with a supported
libfuse 3 high-level lifecycle while keeping the public OCaml API otherwise
stable until M3.

M2 should make the library build against libfuse 3. It should not complete the
FUSE-3-shaped public API or the `Fuse.Fuse_compat` module; those remain M3
work.

## Failures At M1

At the M1 checkpoint, `dune build @install` reached these expected FUSE 3
incompatibilities:

- libfuse 3 rejects `FUSE_USE_VERSION 26`;
- `fuse_setup`, `fuse_teardown`, `fuse_read_cmd`, `fuse_process_cmd`,
  `fuse_exited`, and `struct fuse_cmd` are no longer supported high-level API;
- `struct fuse_operations` no longer has `utime`;
- `readdir` uses the FUSE 3 filler signature and request flags;
- several callbacks add `struct fuse_file_info *` or other parameters.

M2 must handle enough callback ABI drift to compile, but it should avoid
finishing the FUSE 3 public API semantics.

## Recommended Lifecycle

Use the libfuse 3 high-level lifecycle directly instead of `fuse_main`:

1. Initialize `struct fuse_args args = FUSE_ARGS_INIT(argc, argv)`.
2. Parse common command-line options with `fuse_parse_cmdline`.
3. Handle `--help` and `--version` with the libfuse help/version functions.
4. Return a clear error when no mountpoint is provided.
5. Create the high-level handle with `fuse_new`.
6. Mount with `fuse_mount`.
7. Force foreground mode and call `fuse_daemonize(1)`.
8. Get the session with `fuse_get_session`.
9. Install signal handlers with `fuse_set_signal_handlers`.
10. Release the OCaml runtime around `fuse_loop`.
11. Reacquire the OCaml runtime after `fuse_loop` returns.
12. Remove signal handlers, unmount, destroy the FUSE handle, free the parsed
    mountpoint, and free `struct fuse_args` on every cleanup path.

This sequence follows the libfuse 3 high-level examples while keeping cleanup
and runtime-lock boundaries explicit.

## Implementation Checklist

1. Update FUSE API versioning:
   - change `FUSE_USE_VERSION` from `26` to `30` in
     `lib/Fuse_bindings.idl`;
   - change the matching define in `lib/Fuse_util.c`;
   - include `fuse_lowlevel.h` where `fuse_parse_cmdline`,
     `fuse_cmdline_opts`, and signal helpers are needed.
2. Remove libfuse 2 command-loop bindings:
   - remove `type fuse_cmd` from generated OCaml declarations;
   - remove `fuse_read_cmd`, `fuse_process_cmd`, and `fuse_exited` from
     `lib/Fuse_bindings.idl`;
   - remove `mainloop`, `ocaml_fuse_loop_closure`, and
     `ocaml_fuse_is_null` from `lib/Fuse_util.c`;
   - remove the OCaml command loop and callback registration from
     `lib/Fuse_lib.ml`.
3. Replace `ml_fuse_main`:
   - implement the manual high-level lifecycle described above;
   - use `fuse_loop`, not `fuse_loop_mt`;
   - release the OCaml runtime only while blocked in `fuse_loop`;
   - keep existing callback wrappers responsible for acquiring the OCaml
     runtime before they call OCaml.
4. Keep execution single-threaded:
   - force foreground operation for OCaml runtime safety;
   - ignore libfuse's multithreaded default and always call `fuse_loop`;
   - leave `Thread_pool` cleanup as a later non-blocking cleanup unless it is
     required to make M2 compile.
5. Report setup and loop failures clearly:
   - make the internal `ml_fuse_main` binding return an integer status;
   - preserve public `Fuse.main : str array -> operations -> unit`;
   - have `Fuse.main` raise `Failure` with a stage-specific message when
     `ml_fuse_main` returns a nonzero status.
6. Add temporary FUSE 3 callback ABI shims needed for compilation:
   - `init` accepts `struct fuse_conn_info *` and `struct fuse_config *`,
     calls the existing OCaml `unit -> unit` callback, and returns `NULL`;
   - `getattr`, `chmod`, `chown`, and `truncate` accept nullable
     `struct fuse_file_info *` and ignore it;
   - `rename` accepts flags and returns `-EINVAL` for nonzero flags;
   - `readdir` accepts `enum fuse_readdir_flags`, ignores it, and passes
     default filler flags;
   - map the current OCaml `utime` callback to FUSE 3 `utimens` as a temporary
     compatibility shim, converting normal `struct timespec` values to floats
     and returning `-EINVAL` for `UTIME_NOW` or `UTIME_OMIT`.
7. Keep the M3 boundary explicit:
   - do not add the final FUSE-3-shaped `Fuse.operations` record in M2;
   - do not add `Fuse.Fuse_compat` in M2;
   - document every ignored FUSE 3 callback parameter as temporary.

## Accepted Decisions

| Topic | Decision | Reason |
| --- | --- | --- |
| Lifecycle API | Use manual high-level lifecycle, not `fuse_main` | Keeps cleanup, foreground behavior, runtime-lock release, and error mapping explicit. |
| FUSE loop | Use `fuse_loop` for M2 | This keeps the lifecycle skeleton small and avoids registering foreign FUSE worker threads with OCaml before M6 analyzes the multithreaded option. |
| Foreground mode | Force foreground mode | Avoids daemonizing after OCaml runtime startup and matches the OCaml 5 safety requirement. |
| Runtime release | Release only around `fuse_loop` | Callbacks already acquire the runtime before calling OCaml; setup/cleanup stay simple. |
| Error surface | Keep public `Fuse.main` returning `unit`, but raise on nonzero internal status | Preserves the public type while avoiding the current silent setup failure behavior. |
| Callback scope | Add minimal ABI shims only | Lets M2 compile without absorbing the full public API redesign from M3. |
| `utime` bridge | Temporarily route FUSE 3 `utimens` to the old OCaml `utime` callback | Removes the `.utime` build failure while deferring the final `Fuse.utimens` API to M3. |
| Thread pool | Leave `Thread_pool` in the tree for M2 | Removing it is cleanup, not lifecycle migration, and may add unnecessary churn. |

## M2-Specific Decisions

- M2 forces foreground mode even if callers expected libfuse's default
  daemonizing behavior. This is the safest behavior with OCaml 5 and the
  existing FUSE 3 requirement already makes this a breaking migration.

- M2 ignores multithreaded loop options and always calls `fuse_loop`, leaving
  multithreaded support for M6 analysis. Supporting libfuse worker threads
  safely may require extra OCaml runtime registration work, so it should be
  designed as a separate milestone.

- M2 includes temporary callback ABI shims. Otherwise the lifecycle
  implementation cannot be verified with a full build, and the M2/M3 boundary
  remains too vague.

- M2 bridges old `utime` through FUSE 3 `utimens` as a temporary compatibility
  shim. M3 replaces this with the real `Fuse.utimens` API and
  `Fuse.Fuse_compat.utime` bridge.

- M2 setup failures raise OCaml exceptions instead of returning silently. Keep
  the public `unit` return type, but raise `Failure` with a clear
  stage-specific message on command-line, mount, daemonize, signal-handler, or
  loop failure.

## Suggested Internal Status Codes

Use a small internal status enum from `ml_fuse_main` to `Fuse.main`:

- `0`: success;
- `1`: command-line parsing failed;
- `2`: no mountpoint was provided;
- `3`: `fuse_new` failed;
- `4`: `fuse_mount` failed;
- `5`: `fuse_daemonize(1)` failed;
- `6`: `fuse_set_signal_handlers` failed;
- `7`: `fuse_loop` failed.

The exact integer values are internal. `Fuse.main` should convert them to
readable messages.

## Verification

Run these checks for M2:

```sh
tools/format_ocaml lib/Fuse.ml lib/Fuse.mli lib/Fuse_lib.ml
tools/format_c lib/Fuse_util.c lib/Unix_util_stubs.c
dune build @install
```

If `lib/Fuse_bindings.idl` changes cause generated binding issues, inspect the
build output but do not commit generated camlidl files.

M2 does not require a successful mounted e2e run. That remains M4, after the
public API and examples are updated.

## Verification Result

The M2 implementation passes:

```sh
tools/format_ocaml lib/Fuse.ml lib/Fuse.mli lib/Fuse_lib.ml
tools/format_c lib/Fuse_util.c
dune build @install
dune build example/hello.exe example/fusexmp.exe
make e2e-smoke-test
```

`make e2e-smoke-test` builds the test binaries and exits successfully with
`SKIP: /dev/fuse is not available` in the sandbox environment.
