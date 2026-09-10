# Design assets

`AppIcon.swift` draws the app icon with CoreGraphics. Regenerate the asset
catalog after editing it:

```bash
swiftc -O Design/AppIcon.swift -o /tmp/appicon && /tmp/appicon /tmp/icon-1024.png
for px in 16 32 64 128 256 512 1024; do
  sips -z $px $px /tmp/icon-1024.png --out Madroid/Assets.xcassets/AppIcon.appiconset/icon_${px}.png
done
```
