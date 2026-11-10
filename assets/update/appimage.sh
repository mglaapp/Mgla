#!/bin/sh
# Mgla in-app update for the AppImage: put the new file in place of the running one.
# Usage: appimage.sh <pid of the app> <path to the new .AppImage> <path to the installed .AppImage>
# MGLA_UPDATE_NO_OPEN=1 skips relaunching (CI test).
set -u
pid="$1"
new="$2"
target="$3"
exec >>"${TMPDIR:-/tmp}/mgla-update.log" 2>&1
echo "update $(date): pid=$pid new=$new target=$target"

i=0
while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 120 ]; do
  sleep 0.5
  i=$((i + 1))
done

status=1
tmp="$target.new.$$"
if cp "$new" "$tmp" && chmod 755 "$tmp" && mv -f "$tmp" "$target"; then
  status=0
else
  rm -f "$tmp"
fi
rm -f "$new"
echo "done status=$status"
if [ -z "${MGLA_UPDATE_NO_OPEN:-}" ]; then
  setsid "$target" >/dev/null 2>&1 < /dev/null &
fi
exit "$status"
