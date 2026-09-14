#!/bin/zsh
# Repeatable local validation. Optional --apk /path/app.apk --package id runs
# the isolated real-emulator smoke test after static checks and unit tests.
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
AUDIT_OUT=$(mktemp -d "${TMPDIR:-/tmp}/mandroid-audit.XXXXXX")
echo "Audit logs: $AUDIT_OUT"
trap 'echo "Audit failed; inspect logs in $AUDIT_OUT" >&2' ZERR
for script in Scripts/*.sh; do zsh -n "$script"; done
python3 - <<'PY'
import ast
from pathlib import Path
for path in Path('Scripts').glob('*.py'):
    ast.parse(path.read_text(), filename=str(path))
PY
xcodegen generate
echo "Building Debug"
xcodebuild -scheme Mandroid -configuration Debug build > "$AUDIT_OUT/build-debug.log" 2>&1
echo "Running unit tests"
xcodebuild -scheme Mandroid test > "$AUDIT_OUT/tests.log" 2>&1
echo "Building Release"
xcodebuild -scheme Mandroid -configuration Release build > "$AUDIT_OUT/build-release.log" 2>&1
echo "Checking generated sources"
GENERATED_OUTPUT_DIR="$AUDIT_OUT/generated" Scripts/gen-proto.sh > "$AUDIT_OUT/generate.log" 2>&1
diff -rq MandroidKit/Generated "$AUDIT_OUT/generated"
if (( $# )); then
    xcodebuild -scheme Mandroid -configuration Debug -showBuildSettings -json > "$AUDIT_OUT/settings.json"
    APP=$(python3 -c 'import json,sys; s=next(t["buildSettings"] for t in json.load(open(sys.argv[1])) if t["target"]=="Mandroid"); print(s["TARGET_BUILD_DIR"]+"/"+s["FULL_PRODUCT_NAME"])' "$AUDIT_OUT/settings.json")
    python3 Scripts/run-ui-tests.py --app "$APP" "$@" | tee "$AUDIT_OUT/emulator.log"
fi
echo "PASS: build, tests, script syntax and generated-source checks ($AUDIT_OUT)"
