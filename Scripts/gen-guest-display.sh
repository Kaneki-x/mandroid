#!/bin/zsh
# Rebuild the bundled, dependency-free app_process helper. Runtime users do
# not need a JDK or Android build tools. D8 can point to an installed d8 binary.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
: "${ANDROID_JAR:?Set ANDROID_JAR to an installed platforms/android-*/android.jar}"
: "${D8:?Set D8 to the Android build-tools d8 executable}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/classes" "$TMP/dex"
javac --release 8 -classpath "$ANDROID_JAR" -d "$TMP/classes" "$ROOT/Tools/guest-display/"*.java
"$D8" --min-api 31 --output "$TMP/dex" "$TMP/classes/"*.class
# Fixed timestamp and no extra fields make the checked-in resource reproducible.
touch -t 200001010000 "$TMP/dex/classes.dex"
( cd "$TMP/dex" && zip -X -q "$TMP/guest-display.jar" classes.dex )
cp "$TMP/guest-display.jar" "$ROOT/MadroidKit/Resources/guest-display.jar"
