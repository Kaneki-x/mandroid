# App icon

Mandroid keeps its Android-in-a-Mac-window identity with a frosted window,
a bright green silhouette on an opaque navy window, and a deep teal background. A pale titlebar and dark eye cutouts strengthen contrast. The three neutral
titlebar dots stay secondary to the Android mark.

## Source and regeneration

`AppIcon.swift` generates the three transparent SVG layers and Icon Composer
settings in `Mandroid/AppIcon.icon`. Icon Composer orders foreground groups
first. The system supplies the outer mask, highlights, refraction and shadows;
they are not baked into the SVG artwork. The eye holes are silhouette cutouts
so they remain distinct when the system applies a tint.

Run with Xcode 26 selected:

```sh
Scripts/generate-app-icon.sh
xcodegen generate
xcodebuild -scheme Mandroid -configuration Debug build
```

The script compiles the `.icon` with Apple's asset compiler, then
`RenderIcon.swift` renders the full-resolution asset-catalog composite once and derives all seven
legacy PNG sizes. It excludes the small ICNS preview to avoid blurry exports. Keep both the layered icon and the regenerated `AppIcon.appiconset` in
the project: macOS 26 gets the native icon stack, and older releases have the
matching static artwork. The app retains its macOS 15 deployment target.

The generated `Assets.car` contains Aqua, Dark Aqua and tintable icon stacks.
The PNGs are the default light composite; changing their colors does not edit
the native icon. Edit the Swift source and regenerate instead.

See [Apple's Icon Composer guidance](https://developer.apple.com/icon-composer/)
for the platform's layered Liquid Glass icon design.

## Verification (2026-09-15)

- Re-generated the vector bundle into a separate directory and confirmed an
  exact source match.
- Checked all seven PNG dimensions and transparent outer margins; inspected
  the source and built-app composites at 16, 32, 64, 128, 256 and 1024 pixels.
- Inspected the built `Assets.car`: `AppIcon` includes Aqua, Dark Aqua and
  tintable `IconImageStack` records, with separate Android, titlebar and window
  groups. Verified the bundle's icon name, `.icns`, and macOS 15 minimum version.
- Visual inspection covers the default composite. Dark/tinted stacks were
  verified in the compiled catalog, without changing the user's system icon
  appearance or restarting the Dock.
- `Scripts/audit.sh` passed: Debug/Release builds, 74 tests in 24 suites, script
  syntax and generated-source checks. Logs:
  `/var/folders/1z/507v_ftj4sd4vl1s515ycj340000gn/T/mandroid-audit.3TiE6C`.

### Contrast revision

The navy window is opaque so glass translucency cannot wash out the mark.
The green face and dark eye cutouts now separate clearly at Dock sizes. On the
1024px default composite, the sampled face/window luminance ratio at (512,550)
and (512,720) increased from 1.64:1 to 8.79:1. This is a local artwork comparison,
not a claim about every pixel or system appearance.

The PNG exporter now reads the full-resolution catalog rather than the smaller
ICNS compatibility image and rejects an entirely transparent render.
