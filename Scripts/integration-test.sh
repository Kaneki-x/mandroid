#!/bin/zsh
# End-to-end smoke test against the real emulator. Not run in CI.
#
# Prerequisites: a Debug build of the app (xcodebuild -scheme Madroid
# -configuration Debug build), an SDK already installed under
# ~/Library/Application Support/Madroid (or network + ~2.5 GB for the
# first run), and an APK to install (APK=path, defaults to none).
#
# Drives the UI through the debug URL hooks (see Madroid/Launchers/
# DebugHooks.swift) so no Screen Recording / Accessibility permission is needed.
set -euo pipefail

APP="${APP:-$(ls -d ~/Library/Developer/Xcode/DerivedData/Madroid-*/Build/Products/Debug/Madroid.app 2>/dev/null | head -1)}"
APK="${APK:-}"
PKG="${PKG:-com.github.shadowsocks}"
OUT="${OUT:-$(mktemp -d /tmp/aar-it.XXXXXX)}"
AS="$HOME/Library/Application Support/Madroid"

fail() { echo "FAIL: $*" >&2; exit 1; }
snap() {
  rm -rf "$OUT/$1"; open "madroid://debug/snapshot?dir=$OUT/$1"
  for i in $(seq 1 20); do sleep 0.5; [[ -f "$OUT/$1/state.txt" ]] && break; done
  cat "$OUT/$1/state.txt" 2>/dev/null; echo
}
hook() { open "madroid://debug/$1"; }

[[ -d "$APP" ]] || fail "app not built: $APP"
pkill -x Madroid 2>/dev/null || true
sleep 1

echo "==> launching $APP"
T0=$(date +%s)
open "$APP" --args -autoSetup YES
for i in $(seq 1 120); do
  sleep 5
  snap boot >/dev/null 2>&1 || true
  if grep -q '^state=ready' "$OUT/boot/state.txt" 2>/dev/null; then break; fi
  if grep -q '^state=failed' "$OUT/boot/state.txt" 2>/dev/null; then cat "$OUT/boot/state.txt"; fail "boot failed"; fi
done
grep -q '^state=ready' "$OUT/boot/state.txt" || fail "not ready after 10 minutes"
echo "==> ready after $(( $(date +%s) - T0 )) s"

ADB="$AS/sdk/platform-tools/adb"
PORT=$(grep -oE '^adbPort=[0-9]+' "$OUT/boot/state.txt" | cut -d= -f2)
export ANDROID_ADB_SERVER_PORT="$PORT"
echo "==> adb server port $PORT"

if [[ -n "$APK" ]]; then
  echo "==> installing $APK"
  open -a "$APP" "$APK"; sleep 20
fi
snap installed; grep -q "$PKG" "$OUT/installed/state.txt" || fail "$PKG not installed"

echo "==> opening $PKG"
open "madroid://launch/$PKG"; sleep 8
snap opened; grep -qF "sessions=[\"$PKG\"]" "$OUT/opened/state.txt" || fail "no session for $PKG"
secondaries() { "$ADB" shell dumpsys display | grep -oE 'uniqueId="virtual:com.android.emulator.multidisplay:[0-9]+"' | sort -u | wc -l | tr -d ' '; }
[[ $(secondaries) == 1 ]] || fail "expected one secondary display, got $(secondaries)"
python3 - "$OUT/opened/$(ls "$OUT/opened" | grep -v -e state.txt -e Library -e Device | head -1)" <<'PY' || fail "frame is blank"
import sys
from PIL import Image
im = Image.open(sys.argv[1]).convert("RGB")
lo, hi = im.getextrema()[0]
assert hi - lo > 40, f"flat image {im.getextrema()}"
print("frame ok", im.size)
PY

echo "==> input: click, type, scroll, resize, back"
hook "click?pkg=$PKG&x=210&y=450"; sleep 1
hook "type?pkg=$PKG&text=abc"; sleep 1
hook "scroll?pkg=$PKG&x=210&y=600&dy=-300"; sleep 1
hook "resize?pkg=$PKG&w=700&h=480"; sleep 3
"$ADB" shell dumpsys display | grep -qE 'multidisplay:1234562", 1400 x 960' || fail "display was not resized in place"
hook "key?pkg=$PKG&code=33&chars=%5B&cmd=1"; sleep 1
snap after_input >/dev/null

echo "==> closing window"
hook "close?pkg=$PKG"; sleep 3
[[ $(secondaries) == 0 ]] || fail "secondary display not released"
"$ADB" shell pidof "$PKG" >/dev/null && fail "$PKG still running after close" || true

echo "==> quitting"
hook quit
for i in $(seq 1 40); do sleep 1; pgrep -x Madroid >/dev/null || break; done
pgrep -x Madroid >/dev/null && fail "app did not quit"
sleep 2
pgrep -f 'qemu-system-aarch64 -avd runner' >/dev/null && fail "orphaned emulator"
pgrep -f "adb -L tcp:$PORT" >/dev/null && fail "orphaned adb server"
echo "PASS (artifacts in $OUT)"
