#!/bin/sh
# Mgla in-app update on macOS: replace the running .app with the one from the downloaded dmg.
# Usage: macos.sh <pid of the app> <path to .dmg> <path to the installed .app>
# MGLA_UPDATE_NO_OPEN=1 skips relaunching (CI test).
set -u
pid="$1"
dmg="$2"
target="$3"
exec >>"${TMPDIR:-/tmp}/mgla-update.log" 2>&1
echo "update $(date): pid=$pid dmg=$dmg target=$target"

i=0
while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 120 ]; do
  sleep 0.5
  i=$((i + 1))
done

relaunch() {
  [ -n "${MGLA_UPDATE_NO_OPEN:-}" ] || open "$target"
}

mnt=$(mktemp -d "${TMPDIR:-/tmp}/mgla-dmg.XXXXXX")
if ! hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$mnt" "$dmg"; then
  echo "attach failed"
  rmdir "$mnt"
  relaunch
  exit 1
fi
src=$(find "$mnt" -maxdepth 1 -name '*.app' -print | head -n 1)
status=1
if [ -n "$src" ]; then
  new="$target.new.$$"
  old="$target.old.$$"
  rm -rf "$new"
  if ditto "$src" "$new"; then
    if mv "$target" "$old"; then
      if mv "$new" "$target"; then
        rm -rf "$old"
        status=0
      else
        mv "$old" "$target"
      fi
    fi
  fi
  rm -rf "$new"
else
  echo "no .app in the dmg"
fi
hdiutil detach "$mnt" -quiet || hdiutil detach "$mnt" -force -quiet || true
rmdir "$mnt" 2>/dev/null
xattr -dr com.apple.quarantine "$target" 2>/dev/null || true
rm -f "$dmg"
echo "done status=$status"
relaunch
exit "$status"
