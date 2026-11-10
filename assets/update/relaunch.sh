#!/bin/sh
# Start the app again once the old process has left (after a .deb/.rpm update).
# Usage: relaunch.sh <pid of the app> <path to the executable>
set -u
pid="$1"
exe="$2"
i=0
while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 120 ]; do
  sleep 0.5
  i=$((i + 1))
done
[ -n "${MGLA_UPDATE_NO_OPEN:-}" ] || setsid "$exe" >/dev/null 2>&1 < /dev/null &
