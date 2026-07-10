#!/usr/bin/env bash
#
# Verify the packaged AppImage actually starts on a bare system.
#
# A GUI app never exits on its own, so "it works" means: it launches under a
# virtual X server, stays alive, and is still running when we stop it. A
# missing shared library or a broken rpath shows up as an immediate exit.
#
# Run twice: once bare, and once with a .skd as argv[1], which is how the OS
# starts the app when a drawing is double-clicked (task 13.6). A crash while
# parsing that file would otherwise only be found by a user.

set -euo pipefail

APPIMAGE="dist/InkPad-x86_64.AppImage"
GOLDEN="test/fixtures/v1_golden.skd"
ALIVE_SECONDS=10

[[ -x "${APPIMAGE}" ]] || { echo "error: ${APPIMAGE} not found or not executable" >&2; exit 1; }

# No FUSE in containers or on some runners; unpack instead of mounting.
export APPIMAGE_EXTRACT_AND_RUN=1

# stays_alive <label> [args...]
stays_alive() {
  local label="$1"; shift
  local log pid status
  log=$(mktemp)

  xvfb-run -a --server-args="-screen 0 1280x720x24" "${APPIMAGE}" "$@" >"${log}" 2>&1 &
  pid=$!

  sleep "${ALIVE_SECONDS}"

  if ! kill -0 "${pid}" 2>/dev/null; then
    wait "${pid}" && status=0 || status=$?
    echo "FAIL (${label}): exited after less than ${ALIVE_SECONDS}s (status ${status})" >&2
    echo "--- output ---" >&2
    cat "${log}" >&2
    exit 1
  fi

  kill -TERM "${pid}" 2>/dev/null || true
  wait "${pid}" 2>/dev/null || true

  echo "PASS (${label}): stayed alive for ${ALIVE_SECONDS}s"
  if [[ -s "${log}" ]]; then
    echo "--- output (informational) ---"
    cat "${log}"
  fi
}

stays_alive "no arguments"

if [[ -f "${GOLDEN}" ]]; then
  # An absolute path: the AppImage runtime chdirs into its mount point.
  stays_alive "opening a .skd" "$(realpath "${GOLDEN}")"
else
  echo "warning: ${GOLDEN} missing, skipping the argv[1] check" >&2
fi
