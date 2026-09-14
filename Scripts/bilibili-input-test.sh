#!/bin/zsh
# Run against a ready Debug Mandroid with Bilibili installed and onboarding
# completed. Exercises the empty phone field only; never requests a code.
set -euo pipefail
OUT="${OUT:-$(mktemp -d /tmp/mandroid-bili-input.XXXXXX)}"
SCRIPT_DIR="${0:A:h}"
: "${UI_TEST_CONTROL:?Run through Scripts/run-ui-tests.py}"
: "${UI_TEST_DATA_ROOT:?Run through Scripts/run-ui-tests.py}"
AS="$UI_TEST_DATA_ROOT"
url() { python3 "$SCRIPT_DIR/ui-test-command.py" "$1"; }
PKG=tv.danmaku.bili
fail() { echo "FAIL: $*" >&2; exit 1; }
hook() { url "mandroid://debug/$1"; }
snap() {
  mkdir -p "$OUT/$1"
  hook "snapshot?dir=$OUT/$1"
  for i in {1..20}; do [[ -f "$OUT/$1/state.txt" ]] && return; sleep 0.5; done
  fail "snapshot timed out"
}
snap ready
grep -q '^offscreen=true' "$OUT/ready/state.txt" || fail "not offscreen"
grep -q '^visibleWindows=0' "$OUT/ready/state.txt" || fail "visible test window"
grep -q '^state=ready' "$OUT/ready/state.txt" || fail "Mandroid is not ready"
PORT=$(sed -n 's/^adbPort=//p' "$OUT/ready/state.txt")
export ANDROID_SERIAL=$(sed -n 's/^serial=//p' "$OUT/ready/state.txt")
[[ -n "$ANDROID_SERIAL" ]] || fail "missing test emulator serial"
export ANDROID_ADB_SERVER_PORT="$PORT"
export ANDROID_HOME="$AS/sdk" ANDROID_SDK_ROOT="$AS/sdk"
export ANDROID_AVD_HOME="$AS/avd" ANDROID_EMULATOR_HOME="$AS/emulator-home"
ADB="$AS/sdk/platform-tools/adb"
url "mandroid://launch/$PKG"
sleep 7
hook "resize?pkg=$PKG&w=1037&h=648"
sleep 2
# Bilibili's My tab. Read the editor bounds from accessibility after it opens.
hook "click?pkg=$PKG&x=932&y=624"
sleep 3
"$ADB" shell uiautomator dump /data/local/tmp/mandroid-input-test.xml >/dev/null
"$ADB" shell cat /data/local/tmp/mandroid-input-test.xml > "$OUT/before.xml"
python3 - "$OUT/before.xml" > "$OUT/field.txt" <<'PY'
import re,sys,xml.etree.ElementTree as E
fields=[n for n in E.parse(sys.argv[1]).iter('node') if n.get('class')=='android.widget.EditText']
assert len(fields)==1, 'Expected the phone-number field; finish onboarding first'
f=fields[0]
assert f.get('text','')=='', 'Refusing to overwrite existing field content'
x1,y1,x2,y2=map(int,re.findall(r'\d+',f.get('bounds')))
# Probe uses a 2x Retina window, verified below before typing.
print((x1+x2)/4,(y1+y2)/4)
PY
snap focused
grep -qF "rendered=$PKG pixels=2074x1296 input=2074x1296 scale=2.0" "$OUT/focused/state.txt" || fail "test requires a 2x Retina window"
read FIELD_X FIELD_Y < "$OUT/field.txt"
hook "click?pkg=$PKG&x=$FIELD_X&y=$FIELD_Y"
sleep 1
hook "type?pkg=$PKG&text=123"
sleep 1
"$ADB" shell uiautomator dump /data/local/tmp/mandroid-input-test.xml >/dev/null
"$ADB" shell cat /data/local/tmp/mandroid-input-test.xml > "$OUT/typed.xml"
python3 - "$OUT/typed.xml" <<'PY'
import sys,xml.etree.ElementTree as E
assert any(n.get('class')=='android.widget.EditText' and n.get('text')=='123'
           for n in E.parse(sys.argv[1]).iter('node')), 'Typed digits did not reach the editor'
PY
snap typed
hook "key?pkg=$PKG&code=0&chars=a&cmd=1"
hook "key?pkg=$PKG&code=51"
sleep 1
"$ADB" shell uiautomator dump /data/local/tmp/mandroid-input-test.xml >/dev/null
"$ADB" shell cat /data/local/tmp/mandroid-input-test.xml > "$OUT/cleared.xml"
python3 - "$OUT/cleared.xml" <<'PY'
import sys,xml.etree.ElementTree as E
assert any(n.get('class')=='android.widget.EditText' and n.get('text','')==''
           for n in E.parse(sys.argv[1]).iter('node')), 'Select-all/delete failed to clear test digits'
PY
echo "PASS: Bilibili typing and select-all/delete (artifacts in $OUT)"
