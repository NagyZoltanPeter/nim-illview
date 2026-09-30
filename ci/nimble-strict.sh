#!/usr/bin/env bash
#
# Run a nimble task and fail the step when the task fails — including when
# nimble itself does not say so. nimble 0.22.x (shipped with Nim 2.2.10) exits
# 0 after "Error: Exception raised during nimble script execution"; the exit
# code stays the primary signal, the log scan is the backstop. Same pattern
# as nim-brokers' ci/nimble-strict.sh.
#
# Usage:  ci/nimble-strict.sh <task> [args...]

set -uo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <nimble-task> [args...]" >&2
  exit 2
fi

log="$(mktemp -t nimble-strict.XXXXXX)"
trap 'rm -f "$log"' EXIT

nimble "$@" 2>&1 | tee "$log"
rc="${PIPESTATUS[0]}"

if [ "$rc" -ne 0 ]; then
  exit "$rc"
fi

if grep -qE "Exception raised during nimble script execution|\[FAILED\]" "$log"; then
  echo "::error::nimble exited 0 but the task failed (see log above); treating the step as failed."
  exit 1
fi

exit 0
