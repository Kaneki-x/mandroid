#!/bin/zsh
# Requires Xcode 26. Generates vector layers and matching legacy raster assets.
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"
ICON_WORK=$(mktemp -d "${TMPDIR:-/tmp}/mandroid-icon.XXXXXX")
trap 'rm -rf "$ICON_WORK"' EXIT
swift Design/AppIcon.swift
mkdir -p "$ICON_WORK/Preview.bundle/Contents/Resources"
xcrun actool Mandroid/AppIcon.icon \
  --compile "$ICON_WORK/Preview.bundle/Contents/Resources" \
  --output-format human-readable-text --notices --warnings --errors \
  --output-partial-info-plist "$ICON_WORK/Preview.bundle/Contents/Info.plist" \
  --app-icon AppIcon --include-all-app-icons --enable-on-demand-resources NO \
  --development-region en --target-device mac \
  --minimum-deployment-target 15.0 --platform macosx
# Force Bundle.image(forResource:) to use the 1024px asset-catalog composite,
# rather than the compiler's smaller ICNS compatibility representation.
rm "$ICON_WORK/Preview.bundle/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string io.github.madeye.mandroid.iconpreview' "$ICON_WORK/Preview.bundle/Contents/Info.plist"
swift Design/RenderIcon.swift "$ICON_WORK/Preview.bundle" Mandroid/Assets.xcassets/AppIcon.appiconset
