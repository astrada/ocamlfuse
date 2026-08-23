# Recorded Error Review Fixes (PR [#37](https://github.com/astrada/ocamlfuse/pull/37))

## Context

The `toots-upstream-record-exceptions` branch keeps non-`Unix.Unix_error`
exceptions raised by filesystem operations in a native ring and exposes them
through `Fuse.recent_errors` and `Fuse.error_count`. Optional raw-backtrace
capture is controlled by `Fuse.set_backtrace_capture`.

The implementation needs three follow-up fixes before it can be merged:

- `Fuse.recent_errors` dereferences an uninitialized ring when called before
  `Fuse.main`, because the ring is initialized only from `Fuse.main`;
- the ring and capture flag rely on a process-wide OCaml runtime lock, but OCaml
  5 runtime locks are per-domain, so public readers can race with libfuse
  callbacks running on domain 0;
- the C recorder allocates the `Some raw_backtrace` wrapper after the protected
  callback has returned, so that allocation can raise outside an `_exn`
  boundary and prevent the EIO reply and error record.

## Goals

- Make all three recorded-error functions safe before the first call to
  `Fuse.main`.
- Register the ring's global roots exactly once.
- Give readers a coherent snapshot while callbacks record errors concurrently
  on OCaml 5.
- Avoid C data races in the ring metadata and backtrace-capture switch.
- Keep the default recording path free of OCaml allocation.
- Contain every allocation used for optional backtrace capture within an
  exception-safe OCaml callback.
- Preserve the existing public API and the EIO behavior for non-Unix
  exceptions.
- Add deterministic regression coverage for initialization, ring wrapping,
  capture failure, and cross-domain access.

## Non-goals

- Change the treatment of `Unix.Unix_error`; it should continue to be returned
  to libfuse as the corresponding errno and should not enter the ring.
- Change the ring capacity from 1024 entries.
- Add support for multiple concurrent `Fuse.main` mounts in one process.
- Expose testing hooks or ring synchronization primitives in `Fuse.mli`.
- Edit camlidl-generated binding artifacts.

## Design Decisions

### Ring lifetime

Initialize the ring once when the `Fuse` module is initialized and retain the
most recent 1024 errors for the life of the process. Tickets and
`Fuse.error_count` therefore also have process lifetime. This makes repeated
sequential `Fuse.main` calls coherent: neither the entries nor the count are
silently reset by a later invocation.

Update the public documentation to say process lifetime rather than mount
lifetime. If per-mount reset is wanted in the future, add an explicit reset
operation that clears the rooted fields and scalar metadata under the same ring
lock; do not reallocate or re-register the roots.

### Synchronization

Use a dedicated `pthread_mutex_t` for the ring entries, ticket sequence, and
scalar metadata. A libfuse callback and a public reader can hold different OCaml
5 domain locks, so a domain lock is not a substitute for this mutex.

Every potentially blocking mutex acquisition must release the current OCaml
domain lock before waiting and reacquire it afterwards. Keep all OCaml values in
`CAMLparam` or `CAMLlocal` roots across that interval. This avoids blocking a
stop-the-world phase while waiting for another domain to release the ring
mutex.

Do not allocate, raise, or call back into OCaml while holding the ring mutex.
An OCaml allocation can raise and bypass C cleanup, which would leave the mutex
locked. It can also require cooperation from other domains.

Use a C11 atomic value for the backtrace-capture switch. Recording must inspect
that switch before making the immediate backtrace callback, so taking a
potentially blocking ring lock first would unnecessarily separate capture from
the original raise. Atomic load/store semantics are sufficient for this
independent boolean setting.

### Reader snapshots

`Fuse.recent_errors` must not build returned OCaml records directly from a ring
that can change on another domain. It should:

1. Allocate fixed-capacity rooted snapshot arrays before acquiring the mutex.
2. Acquire the ring mutex using the domain-lock-safe helper.
3. Copy every valid slot's rooted values and scalar metadata into those
   snapshots without allocating. Use `caml_modify` when storing OCaml values in
   the snapshot arrays.
4. Release the ring mutex.
5. Sort the copied metadata by ticket and allocate the exact result array and
   `recorded_error` records after the lock has been released.

The snapshot should include the ticket, time, operation-name pointer, path,
exception, and optional raw backtrace for each copied slot. Operation names are
string literals and remain valid after unlocking. Rooted snapshot arrays keep
the OCaml values alive and movable while the returned records are allocated.

This design avoids both partial records and allocations under the native
mutex. It also makes the returned array a point-in-time snapshot even if the
ring wraps while the result is being constructed.

## Implementation Plan

### 1. Initialize the ring at module load

Split one-time binding initialization from `Fuse.main` lifecycle work.

1. Keep the error-vector inversion and ring allocation in a one-time C
   initializer.
2. Register `ml_fuse_err_empty`, `ml_fuse_err_exns`,
   `ml_fuse_err_paths`, and `ml_fuse_err_backtraces` as global roots exactly
   once.
3. Initialize every ticket to `-1`, initialize scalar metadata, and leave every
   OCaml slot at its safe empty value.
4. Call the initializer from `Fuse.ml` module initialization, after registering
   the named backtrace-capture callback.
5. Remove the initializer call from `Fuse.main` so repeated main invocations do
   not allocate new arrays or register the same root addresses again.

After this step, the following must be valid before any mount attempt:

```ocaml
assert (Fuse.error_count () = 0);
assert (Fuse.recent_errors () = [||]);
Fuse.set_backtrace_capture true;
Fuse.set_backtrace_capture false
```

Keep generated `Fuse_bindings.ml`, `Fuse_bindings.mli`,
`Fuse_bindings_stubs.c`, and `Fuse_bindings.h` untouched. If the camlidl
initializer declaration changes, edit `lib/Fuse_bindings.idl` and let Dune
regenerate its outputs.

### 2. Make backtrace capture allocation-safe

Change the named OCaml callback to construct the complete option value inside
an exception handler:

```ocaml
let capture_backtrace () =
  try Some (Printexc.get_raw_backtrace ()) with _ -> None
```

Register that function as `ml_fuse_capture_backtrace`. The C recorder should
use the returned option directly and must remove its current
`caml_alloc_small(1, 0)` call.

Continue to invoke the callback with `caml_callback_exn` as a final containment
boundary. If the callback still returns an exception result, clear that encoded
exception from any local GC root and record `None`. The original filesystem
exception, operation, and path must still be stored, and the callback must
still return `-EIO`.

Backtrace capture must happen immediately after detecting the exception result
and before any unrelated OCaml callback. Only after capture has produced a
rooted option value should recording wait for the ring mutex.

### 3. Synchronize writers and scalar accessors

Add a dedicated error-ring mutex and small lock/unlock helpers in
`lib/Fuse_util.c`.

The lock helper should:

1. release the current OCaml domain lock;
2. acquire the pthread mutex;
3. reacquire the OCaml domain lock before returning.

All callers must already have registered the current C thread with the OCaml
runtime and hold its domain lock. The unlock helper can release the pthread
mutex while retaining the OCaml domain lock.

Update `ml_fuse_record_exception` so that it:

1. roots the exception, path, and captured-backtrace option;
2. performs optional backtrace capture without the ring mutex;
3. acquires the ring mutex;
4. assigns the next ticket and slot;
5. updates the rooted arrays with `caml_modify`;
6. updates the operation, timestamp, and ticket metadata, publishing the ticket
   only after its other fields are complete;
7. releases the mutex before returning.

The mutex, rather than publication comments alone, provides the ordering seen
by readers. Keep the ticket-last convention as an additional invariant and to
make unwritten slots explicit.

Update `ml_fuse_error_count` to read the sequence under the same mutex. Convert
the copied scalar to an OCaml integer only after unlocking.

Replace the plain `ml_fuse_capture_backtraces` integer with an atomic boolean or
atomic integer. Use an atomic load in the recorder and an atomic store in
`ml_fuse_set_backtrace_capture`.

### 4. Return coherent recent-error snapshots

Rewrite `ml_fuse_recent_errors` around the snapshot design above.

Before locking, allocate and root enough OCaml storage for the path, exception,
and backtrace values of all 1024 possible entries. Use fixed-size C arrays for
the copied tickets, timestamps, operation-name pointers, and any ordering
indices.

While holding the ring mutex:

- scan the ring once;
- copy only slots whose ticket is nonnegative;
- copy all fields belonging to a slot before advancing the snapshot count;
- perform no OCaml allocation and no callback.

After unlocking:

- sort snapshot indices by their copied tickets;
- allocate a result array of the copied count;
- construct each six-field `recorded_error` from snapshot data;
- copy operation names into OCaml strings;
- return entries oldest first.

Audit every early return and exception-capable operation to ensure none occurs
while the mutex is held.

### 5. Add regression coverage

#### Public pre-main unit test

Add `test/unit/recorded_errors_test.ml` and a corresponding Dune test stanza.
Without calling `Fuse.main`, assert that:

- `Fuse.recent_errors ()` returns an empty array;
- `Fuse.error_count ()` returns zero;
- enabling and disabling backtrace capture succeeds;
- a major collection between those calls does not invalidate the rooted ring.

This test should call the public functions directly so the original
pre-initialization segfault fails the test process.

#### Internal recorder tests

Add a test-local C stub that can pass a supplied exception and path to the
native recorder. Make the recorder available as an internal C symbol if
necessary, but do not add any testing value to `Fuse.ml` or `Fuse.mli`.

Use that hook in a separate test process to verify:

- one recorded exception increments `error_count` and round-trips its operation,
  path, and exception;
- more than 1024 records retain exactly the newest 1024 entries in increasing
  ticket order;
- ticket gaps and the total count remain correct after wrapping;
- replacing the named capture callback with one that raises `Out_of_memory`
  still records the original exception with `backtrace = None`.

The forced callback failure is deterministic and tests the containment path
without trying to exhaust the test runner's address space.

#### OCaml 5 domain stress test

Add an OCaml-5-only Dune test stanza, enabled with an `ocaml_version` condition.
Use the internal recorder hook to run enough writes to wrap the ring while
other domains repeatedly call `Fuse.recent_errors`, `Fuse.error_count`, and
toggle backtrace capture.

Every returned entry must remain type-correct, tickets within each snapshot
must be strictly increasing, and the process must complete without a crash or
deadlock. It is acceptable for successive snapshots to have different bounds
while writers are active.

Compile no reference to `Domain` on supported OCaml 4 switches; the test must
be disabled at the Dune stanza level there.

#### Mounted behavior

Retain and extend the existing recorded-exception e2e test so that it continues
to prove the production callback path:

- returns EIO for a non-Unix exception;
- records the operation and path;
- omits a backtrace while capture is off;
- records a raw backtrace while capture is on.

The unit hook tests ring mechanics, but it does not replace this mounted
libfuse-to-OCaml-to-C integration check.

### 6. Update comments and public documentation

Update `lib/Fuse.mli`, `docs/release-notes.md`, and adjacent C comments to
describe the final invariants:

- the ring and count have process lifetime;
- `recent_errors` is safe before, during, and after a mount;
- returned arrays are coherent snapshots and may immediately become stale;
- capture failure keeps the error entry and omits only its backtrace;
- the native mutex, not the OCaml runtime lock, serializes ring state across
  domains;
- the capture switch is atomic.

Keep the documentation descriptive of current behavior rather than referring
to the review or the previous broken implementation.

## Formatting and Validation

After implementing the changes:

1. Format touched C and OCaml sources:

   ```sh
   tools/format_c lib/Fuse_util.c test/unit/<changed-c-stubs>
   tools/format_ocaml lib/Fuse.ml lib/Fuse.mli \
     test/unit/<changed-ml-files> test/e2e/testfs.ml test/e2e/client.ml
   ```

2. Run the required build and unit tests sequentially:

   ```sh
   dune build @install
   make test
   ```

3. Build the public examples:

   ```sh
   dune build example/hello.exe example/fusexmp.exe
   ```

4. Run mounted validation outside the sandbox:

   ```sh
   make e2e-smoke-test
   make e2e
   make e2e-single-threaded
   make e2e-multithreaded
   ```

5. From a TSAN-enabled OCaml 5 switch, follow `docs/tsan-testing.md` and run at
   least:

   ```sh
   dune clean
   dune build @install
   dune runtest
   dune build example/hello.exe example/fusexmp.exe
   ```

   Then run the suppressed multithreaded mounted suite outside the sandbox:

   ```sh
   OCAMLFUSE_E2E_REQUIRE_FUSE=1 \
   TSAN_OPTIONS="halt_on_error=1:second_deadlock_stack=1:suppressions=$PWD/tsan_suppression.txt" \
   make e2e-multithreaded
   ```

The OCaml 5 domain stress test must pass under TSAN without a report in the
error-ring state, snapshot code, or capture flag.

## Acceptance Criteria

- `Fuse.recent_errors`, `Fuse.error_count`, and
  `Fuse.set_backtrace_capture` are safe before `Fuse.main`.
- Global roots are allocated and registered once per process.
- Repeated sequential `Fuse.main` calls do not discard or inconsistently reset
  the ring and total count.
- No error-ring field or scalar is read concurrently without the mutex or an
  appropriate atomic operation.
- No code path allocates or calls OCaml while holding the ring mutex.
- A recent-errors result contains a coherent, oldest-first snapshot.
- Ring wrapping retains the newest 1024 records with correct tickets.
- Backtrace capture success stores `Some raw_backtrace`.
- Backtrace capture failure stores `None`, keeps the original exception entry,
  and still returns EIO to the filesystem caller.
- OCaml 4 builds omit the domain-only test and continue to pass.
- OCaml 5 domain and TSAN tests complete without races, crashes, or deadlocks.
- Build, unit, example, and mounted test commands pass.

## Implementation Validation

The implementation passes the OCaml 5.4 and OCaml 4.14 build and unit suites,
the public example build, and the default, explicit single-threaded, and
explicit multithreaded mounted suites. The OCaml 5 domain stress test is part of
the unit suite.

The TSAN-enabled switch also passes a clean build, the complete unit suite, the
public example build, and the suppressed explicit multithreaded mounted suite.
That validation includes both the OCaml 5 domain stress test and libfuse-created
worker callbacks, with no sanitizer report in the error ring or capture flag.
