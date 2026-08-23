#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/../.." && pwd)
mode=${1:-smoke}
require_fuse=${OCAMLFUSE_E2E_REQUIRE_FUSE:-0}
loop_mode=${OCAMLFUSE_E2E_LOOP_MODE:-default}

case "$mode" in
  smoke | full) ;;
  *)
    echo "usage: test/e2e/run.sh [smoke|full]" >&2
    exit 2
    ;;
esac

case "$loop_mode" in
  default | single | multi) ;;
  *)
    echo "unsupported OCAMLFUSE_E2E_LOOP_MODE: $loop_mode" >&2
    exit 2
    ;;
esac

cd "$repo_root"

dune build test/e2e/testfs.exe test/e2e/client.exe test/e2e/compat_compile.exe

skip_or_fail() {
  local message=$1
  if [ "$require_fuse" = "1" ]; then
    echo "FAIL: $message" >&2
    exit 1
  fi
  echo "SKIP: $message"
  exit 0
}

if [ "$(uname -s)" != "Linux" ]; then
  skip_or_fail "ocamlfuse e2e tests currently target Linux only"
fi

if [ ! -e /dev/fuse ]; then
  skip_or_fail "/dev/fuse is not available"
fi

if [ ! -r /dev/fuse ] || [ ! -w /dev/fuse ]; then
  skip_or_fail "/dev/fuse is not readable and writable by this user"
fi

if command -v fusermount >/dev/null 2>&1; then
  unmount_cmd=(fusermount -u)
elif command -v fusermount3 >/dev/null 2>&1; then
  unmount_cmd=(fusermount3 -u)
elif command -v umount >/dev/null 2>&1; then
  unmount_cmd=(umount)
else
  skip_or_fail "no FUSE unmount command found"
fi

if command -v timeout >/dev/null 2>&1; then
  run_with_timeout() {
    local seconds=$1
    shift
    timeout "$seconds" "$@"
  }
else
  run_with_timeout() {
    shift
  "$@"
  }
fi

tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/ocamlfuse-e2e.XXXXXX")
backing_root="$tmp_root/backing"
mountpoint="$tmp_root/mnt"
mt_control_dir="$tmp_root/mt"
mt_block_marker="$mt_control_dir/block.marker"
mt_release_fifo="$mt_control_dir/release.fifo"
callback_log="$tmp_root/callbacks.log"
ready_marker="$tmp_root/ready"
exited_marker="$tmp_root/exited"
invalidate_fifo="$tmp_root/invalidate.fifo"
invalidate_ack="$tmp_root/invalidate.ack"
invalidate_failure="$tmp_root/invalidate.failure"
invalidate_stress_marker="$tmp_root/invalidate-stress.marker"
testfs_stdout="$tmp_root/testfs.stdout"
testfs_stderr="$tmp_root/testfs.stderr"
fs_pid=

mkdir "$backing_root" "$mountpoint" "$mt_control_dir"
mkfifo "$mt_release_fifo" "$invalidate_fifo"
touch "$callback_log"

cleanup() {
  local status=$?
  trap - EXIT INT TERM
  set +e

  if [ -n "${mountpoint:-}" ] && [ -d "$mountpoint" ]; then
    "${unmount_cmd[@]}" "$mountpoint" >/dev/null 2>&1
  fi

  if [ -n "${fs_pid:-}" ] && kill -0 "$fs_pid" >/dev/null 2>&1; then
    kill "$fs_pid" >/dev/null 2>&1
    sleep 0.2
    if kill -0 "$fs_pid" >/dev/null 2>&1; then
      kill -9 "$fs_pid" >/dev/null 2>&1
    fi
    wait "$fs_pid" >/dev/null 2>&1
  fi

  if [ -n "${tmp_root:-}" ]; then
    rm -rf "$tmp_root"
  fi

  exit "$status"
}

trap cleanup EXIT INT TERM

fuse_args=("$mountpoint" -f -o fsname=ocamlfuse_e2e)
if [ "$loop_mode" = "single" ]; then
  fuse_args+=(-s)
fi

OCAMLFUSE_E2E_BACKING_ROOT="$backing_root" \
OCAMLFUSE_E2E_LOG="$callback_log" \
OCAMLFUSE_E2E_READY="$ready_marker" \
OCAMLFUSE_E2E_EXITED="$exited_marker" \
OCAMLFUSE_E2E_INVALIDATE_FIFO="$invalidate_fifo" \
OCAMLFUSE_E2E_INVALIDATE_ACK="$invalidate_ack" \
OCAMLFUSE_E2E_INVALIDATE_FAILURE="$invalidate_failure" \
OCAMLFUSE_E2E_INVALIDATE_STRESS_MARKER="$invalidate_stress_marker" \
OCAMLFUSE_E2E_LOOP_MODE="$loop_mode" \
OCAMLFUSE_E2E_MT_BLOCK_MARKER="$mt_block_marker" \
OCAMLFUSE_E2E_MT_RELEASE_FIFO="$mt_release_fifo" \
  _build/default/test/e2e/testfs.exe "${fuse_args[@]}" \
    >"$testfs_stdout" 2>"$testfs_stderr" &
fs_pid=$!

deadline=$((SECONDS + 10))
while [ ! -e "$ready_marker" ]; do
  if ! kill -0 "$fs_pid" >/dev/null 2>&1; then
    if grep -qiE 'fuse:|fusermount|permission denied|operation not permitted|/dev/fuse' "$testfs_stderr"; then
      skip_or_fail "could not mount FUSE filesystem"
    fi
    echo "test filesystem exited before becoming ready" >&2
    cat "$testfs_stdout" >&2
    cat "$testfs_stderr" >&2
    exit 1
  fi

  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "timed out waiting for FUSE filesystem readiness" >&2
    cat "$testfs_stdout" >&2
    cat "$testfs_stderr" >&2
    exit 1
  fi

  sleep 0.1
done

set +e
OCAMLFUSE_E2E_MODE="$mode" \
OCAMLFUSE_E2E_MOUNTPOINT="$mountpoint" \
OCAMLFUSE_E2E_BACKING_ROOT="$backing_root" \
OCAMLFUSE_E2E_LOG="$callback_log" \
OCAMLFUSE_E2E_INVALIDATE_FIFO="$invalidate_fifo" \
OCAMLFUSE_E2E_INVALIDATE_ACK="$invalidate_ack" \
OCAMLFUSE_E2E_INVALIDATE_FAILURE="$invalidate_failure" \
OCAMLFUSE_E2E_LOOP_MODE="$loop_mode" \
OCAMLFUSE_E2E_MT_BLOCK_MARKER="$mt_block_marker" \
OCAMLFUSE_E2E_MT_RELEASE_FIFO="$mt_release_fifo" \
  run_with_timeout 30 _build/default/test/e2e/client.exe
status=$?
set -e

if [ "$status" -ne 0 ]; then
  echo "e2e client failed" >&2
  echo "--- callback log ---" >&2
  cat "$callback_log" >&2
  echo "--- testfs stdout ---" >&2
  cat "$testfs_stdout" >&2
  echo "--- testfs stderr ---" >&2
  cat "$testfs_stderr" >&2
  exit "$status"
fi

rm -f "$invalidate_ack" "$invalidate_failure" "$invalidate_stress_marker"
printf 'stress /\n' >"$invalidate_fifo"

deadline=$((SECONDS + 10))
while [ ! -e "$invalidate_stress_marker" ]; do
  if ! kill -0 "$fs_pid" >/dev/null 2>&1; then
    echo "test filesystem exited before invalidation stress started" >&2
    cat "$testfs_stdout" >&2
    cat "$testfs_stderr" >&2
    exit 1
  fi

  if [ -e "$invalidate_failure" ]; then
    echo "invalidation worker failed before teardown" >&2
    cat "$invalidate_failure" >&2
    exit 1
  fi

  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "timed out waiting for invalidation stress to start" >&2
    exit 1
  fi

  sleep 0.02
done

if ! "${unmount_cmd[@]}" "$mountpoint"; then
  echo "failed to unmount FUSE filesystem after e2e tests" >&2
  exit 1
fi

deadline=$((SECONDS + 10))
while [ ! -e "$exited_marker" ]; do
  if ! kill -0 "$fs_pid" >/dev/null 2>&1; then
    break
  fi

  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "timed out waiting for test filesystem to exit cleanly" >&2
    cat "$testfs_stdout" >&2
    cat "$testfs_stderr" >&2
    exit 1
  fi

  sleep 0.02
done

set +e
wait "$fs_pid"
fs_status=$?
set -e
fs_pid=

if [ "$fs_status" -ne 0 ] || [ ! -e "$exited_marker" ]; then
  echo "test filesystem did not exit cleanly" >&2
  if [ -e "$invalidate_failure" ]; then
    cat "$invalidate_failure" >&2
  fi
  cat "$testfs_stdout" >&2
  cat "$testfs_stderr" >&2
  exit 1
fi

if [ -e "$invalidate_failure" ]; then
  echo "invalidation worker reported a teardown failure" >&2
  cat "$invalidate_failure" >&2
  exit 1
fi
