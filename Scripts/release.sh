#!/bin/zsh
# Builds a Release archive, signs with Developer ID, notarizes and staples.
#
# Required environment:
#   DEVELOPER_ID   e.g. "Developer ID Application: Jane Doe (TEAMID)"
#   TEAM_ID        e.g. "TEAMID"
#   NOTARY_PROFILE keychain profile created with
#                  `xcrun notarytool store-credentials <name> --apple-id … --team-id … --password …`
# Output: build/Madroid.app and build/Madroid.zip
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build"
: "${DEVELOPER_ID:?}" "${TEAM_ID:?}" "${NOTARY_PROFILE:?}"

cd "$ROOT"
xcodegen generate
rm -rf "$OUT"; mkdir -p "$OUT"
xcodebuild -scheme Madroid -configuration Release \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID" DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Manual \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
  build | tail -3
# Keep builds in Xcode's normal DerivedData location: LaunchServices can
# stall while registering applications built under an external volume.
xcodebuild -scheme Madroid -configuration Release -showBuildSettings -json > "$OUT/settings.json"
APP=$(python3 -c 'import json,sys; s=next(t["buildSettings"] for t in json.load(open(sys.argv[1])) if t["target"]=="Madroid"); print(s["TARGET_BUILD_DIR"]+"/"+s["FULL_PRODUCT_NAME"])' "$OUT/settings.json")
cp -R "$APP" "$OUT/"
APP="$OUT/Madroid.app"

codesign --verify --deep --strict --verbose=2 "$APP"
ditto -c -k --keepParent "$APP" "$OUT/Madroid.zip"
xcrun notarytool submit "$OUT/Madroid.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
ditto -c -k --keepParent "$APP" "$OUT/Madroid.zip"
spctl --assess --type execute --verbose "$APP"
echo "release ready: $OUT/Madroid.zip"
