#!/usr/bin/env bash
# Runs the in-app update scripts (assets/update) for real: macOS swaps an .app from a dmg,
# Linux swaps an AppImage. CI runs it on macos-latest and ubuntu-latest.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export MGLA_UPDATE_NO_OPEN=1
export TMPDIR="$work"
failures=0

check() {
  if eval "$2"; then
    echo "PASS  $1"
  else
    echo "FAIL  $1"
    failures=$((failures + 1))
  fi
}

# A process that stands in for the running app: the script must wait for it to leave.
fake_app() {
  sleep 2 >/dev/null 2>&1 &
  echo $!
}

test_appimage() {
  local dir="$work/appimage"
  mkdir -p "$dir"
  printf 'old' >"$dir/Mgla.AppImage"
  printf 'new' >"$dir/download.AppImage"
  local pid started
  pid=$(fake_app)
  started=$(date +%s)
  sh "$root/assets/update/appimage.sh" "$pid" "$dir/download.AppImage" "$dir/Mgla.AppImage"
  local status=$?
  check "appimage: exit 0" "[ $status -eq 0 ]"
  check "appimage: waited for the app to leave" "[ \$(( \$(date +%s) - $started )) -ge 1 ]"
  check "appimage: new file in place" "[ \"\$(cat '$dir/Mgla.AppImage')\" = new ]"
  check "appimage: executable" "[ -x '$dir/Mgla.AppImage' ]"
  check "appimage: download removed" "[ ! -e '$dir/download.AppImage' ]"
  check "appimage: no leftovers" "[ \$(ls '$dir' | wc -l) -eq 1 ]"

  # Control: an unwritable folder must leave the installed file untouched and fail.
  local ro="$work/readonly"
  mkdir -p "$ro"
  printf 'old' >"$ro/Mgla.AppImage"
  printf 'new' >"$work/download2.AppImage"
  chmod 555 "$ro"
  sh "$root/assets/update/appimage.sh" 999999 "$work/download2.AppImage" "$ro/Mgla.AppImage"
  status=$?
  chmod 755 "$ro"
  if [ "$(id -u)" -ne 0 ]; then
    check "appimage control: unwritable folder fails" "[ $status -ne 0 ]"
    check "appimage control: old file kept" "[ \"\$(cat '$ro/Mgla.AppImage')\" = old ]"
  fi
}

make_app() {
  mkdir -p "$1/Mgla.app/Contents/MacOS"
  printf '%s' "$2" >"$1/Mgla.app/Contents/MacOS/Mgla"
}

test_macos() {
  local src="$work/src" dest="$work/Applications"
  make_app "$src" new
  make_app "$dest" old
  hdiutil create -quiet -volname Mgla -srcfolder "$src" -format UDZO "$work/Mgla.dmg"
  local pid
  pid=$(fake_app)
  sh "$root/assets/update/macos.sh" "$pid" "$work/Mgla.dmg" "$dest/Mgla.app"
  local status=$?
  check "macos: exit 0" "[ $status -eq 0 ]"
  check "macos: new app in place" "[ \"\$(cat '$dest/Mgla.app/Contents/MacOS/Mgla')\" = new ]"
  check "macos: dmg removed" "[ ! -e '$work/Mgla.dmg' ]"
  check "macos: no .new/.old leftovers" "[ \$(ls '$dest' | wc -l) -eq 1 ]"
  check "macos: dmg detached" "! hdiutil info | grep -q mgla-dmg"

  # Control: a broken dmg must fail and keep the installed app.
  printf 'not a dmg' >"$work/broken.dmg"
  sh "$root/assets/update/macos.sh" 999999 "$work/broken.dmg" "$dest/Mgla.app"
  status=$?
  check "macos control: broken dmg fails" "[ $status -ne 0 ]"
  check "macos control: installed app kept" "[ \"\$(cat '$dest/Mgla.app/Contents/MacOS/Mgla')\" = new ]"
}

test_relaunch() {
  local start
  start=$(date +%s)
  sh "$root/assets/update/relaunch.sh" 999999 /bin/true
  check "relaunch: a gone process is not waited for" "[ \$(( \$(date +%s) - $start )) -lt 3 ]"
}

case "$(uname -s)" in
  Darwin) test_macos ;;
  *) test_appimage ;;
esac
test_relaunch

echo "failures: $failures"
[ "$failures" -eq 0 ]
