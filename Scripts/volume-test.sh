#!/bin/zsh
# Native media-volume integration check in an isolated, hidden app.
set -euo pipefail
: "${UI_TEST_CONTROL:?Run through Scripts/run-ui-tests.py --test volume}"
: "${UI_TEST_DATA_ROOT:?Missing isolated data root}"
: "${OUT:?Missing artifacts directory}"
SCRIPT_DIR="${0:A:h}"
hook() { python3 "$SCRIPT_DIR/ui-test-command.py" "mandroid://debug/$1"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
snap() {
  rm -f "$OUT/state.txt"
  hook "snapshot?dir=$OUT"
  for i in {1..40}; do [[ -f "$OUT/state.txt" ]] && break; sleep 0.25; done
  grep -q '^offscreen=true' "$OUT/state.txt" || fail "not offscreen"
  grep -q '^visibleWindows=0' "$OUT/state.txt" || fail "visible test window"
}
for i in {1..120}; do
  sleep 2
  snap
  grep -q '^state=ready' "$OUT/state.txt" && break
  grep -q '^state=failed' "$OUT/state.txt" && fail "boot failed"
done
grep -q '^state=ready' "$OUT/state.txt" || fail "boot timed out"
PORT=$(sed -n 's/^adbPort=//p' "$OUT/state.txt")
export ANDROID_SERIAL=$(sed -n 's/^serial=//p' "$OUT/state.txt")
export ANDROID_HOME="$UI_TEST_DATA_ROOT/sdk" ANDROID_SDK_ROOT="$UI_TEST_DATA_ROOT/sdk"
export ANDROID_AVD_HOME="$UI_TEST_DATA_ROOT/avd" ANDROID_EMULATOR_HOME="$UI_TEST_DATA_ROOT/emulator-home" ADB_USB=0
ADB="$ANDROID_HOME/platform-tools/adb"
readVolume() { "$ADB" -P "$PORT" shell cmd media_session volume --stream 3 --get; }
BEFORE=$(readVolume | sed -n 's/.*volume is \([0-9]*\) in.*/\1/p')
MAX=$(readVolume | sed -n 's/.*range \[0\.\.\([0-9]*\)\].*/\1/p')
[[ -n "$BEFORE" && -n "$MAX" ]] || fail "invalid native volume range"
trap '"$ADB" -P "$PORT" shell "CLASSPATH=/data/local/tmp/mandroid-display-ime.jar app_process / SetMediaVolume $BEFORE" >/dev/null' EXIT
for percent in 0 100 50; do
  expected=$(( (MAX * percent + 50) / 100 ))
  hook "volume?percent=$percent"
  for i in {1..30}; do
    sleep 0.2
    readVolume > "$OUT/volume-$percent.txt"
    grep -qF "volume is $expected in range" "$OUT/volume-$percent.txt" && break
  done
  grep -qF "volume is $expected in range" "$OUT/volume-$percent.txt" || fail "volume $percent% failed"
done
hook settings
sleep 2
snap
echo "PASS: native media volume 0%, 100%, 50%; Settings offscreen; restoring $BEFORE/$MAX (artifacts: $OUT)"
