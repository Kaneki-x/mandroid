#!/bin/zsh
# Rebuild the bundled Android proxy helper with the same signing key for upgrades.
set -euo pipefail
ROOT="${0:A:h:h}"
: "${ANDROID_JAR:?}" "${ANDROID_BUILD_TOOLS:?}" "${KEYSTORE_PATH:?}" "${KEY_ALIAS:?}" "${KEYSTORE_PASSWORD:?}"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$STAGING/classes" "$STAGING/dex"
javac --release 8 -classpath "$ANDROID_JAR" -d "$STAGING/classes" "$ROOT"/Tools/proxy-agent/src/io/github/madeye/mandroid/proxy/*.java
"$ANDROID_BUILD_TOOLS/d8" --min-api 29 --lib "$ANDROID_JAR" --output "$STAGING/dex" "$STAGING"/classes/io/github/madeye/mandroid/proxy/*.class
"$ANDROID_BUILD_TOOLS/aapt2" link -o "$STAGING/unsigned.apk" --manifest "$ROOT/Tools/proxy-agent/AndroidManifest.xml" -I "$ANDROID_JAR"
touch -t 200001010000 "$STAGING/dex/classes.dex"
(cd "$STAGING/dex" && zip -X -q "$STAGING/unsigned.apk" classes.dex)
"$ANDROID_BUILD_TOOLS/zipalign" -f 4 "$STAGING/unsigned.apk" "$STAGING/aligned.apk"
"$ANDROID_BUILD_TOOLS/apksigner" sign --ks "$KEYSTORE_PATH" --ks-key-alias "$KEY_ALIAS" --ks-pass env:KEYSTORE_PASSWORD --out "$STAGING/proxy-agent.apk" "$STAGING/aligned.apk"
"$ANDROID_BUILD_TOOLS/apksigner" verify "$STAGING/proxy-agent.apk"
cp "$STAGING/proxy-agent.apk" "$ROOT/MandroidKit/Resources/proxy-agent.apk"
