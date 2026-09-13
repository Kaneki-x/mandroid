# Madroid

Run Android apps on your Mac as if they were native macOS apps. Each Android
app gets its own window with a normal title bar, resizes like a Mac window,
shares the clipboard, answers to Cmd shortcuts, and shows up in the Dock and
Spotlight — no phone frame, no Android status or navigation bars.

**Status: working prototype.** Phases 0–3 of the plan are implemented and
exercised end to end (first-run download, boot, app windows with touch,
keyboard, scroll, free resize, clipboard, launcher stubs). Not yet signed or
notarized for distribution; build it from source. The design and the phased
plan live in [`docs/`](docs/):

- [docs/DESIGN.md](docs/DESIGN.md) — architecture, verified facts, mechanisms, risks
- [docs/PLAN.md](docs/PLAN.md) — phases with "done when" criteria and status
- [docs/SPIKE-NOTES.md](docs/SPIKE-NOTES.md) — measurements behind the design decisions
- [docs/compat.md](docs/compat.md) — per-app compatibility notes

## Building

```bash
brew install xcodegen protobuf   # protobuf only if you regenerate gRPC code
xcodegen generate
xcodebuild -scheme Madroid -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/Madroid-*/Build/Products/Debug/Madroid.app
```

On first launch the app lists what it will download (about 2.5 GB from
`dl.google.com`) and installs everything under
`~/Library/Application Support/Madroid/`. On Macs set to mainland China the
download comes from the Tencent Cloud mirror instead (Aliyun for aapt2); the
choice can be changed on the setup screen or in Settings ▸ Downloads.

## How it works

The app downloads the stock Android Emulator, platform-tools and a Google Play
system image on first launch and boots the emulator headless. For every
Android app you open it creates a private virtual display inside the emulator,
launches the app on that display, and streams the display's pixels into a
macOS window over the emulator's gRPC API. The built-in device uses a
Pixel Tablet-sized 2560×1600 display at 320 dpi; app windows render at their
own physical pixel size and reconfigure Android when resized. New windows
default to 1280×800 points (2560×1600 pixels on a 2× Retina screen), scaled
down to fit smaller screens. Mouse, keyboard, scroll and
clipboard are translated back the same way.

Settings includes a media-volume slider for all Android apps. It controls the
guest's native media stream, supports mute, and restores your chosen level on
restart. Audio continues to play through the emulator's native macOS backend.

## Requirements

- A Mac with Apple silicon (M1 or later) running macOS 15 or later. Intel
  Macs are not supported; the app is built for arm64 only.
- About 2.5 GB of disk for the emulator and system image, downloaded on first
  launch, plus space for Android apps and data
- No Java, Android Studio or SDK installation needed

## Limitations

- At most three Android app windows at a time per emulator instance (an
  emulator limit); additional windows are parked and resume on click
- Apps that require Play Integrity attestation (many banking and DRM apps)
  detect the emulator and will not run

## Roadmap

See [docs/PLAN.md](docs/PLAN.md) for what is done. Next candidates: signed
and notarized releases, an audio mute switch, an Android-side display
provider to lift the three-window cap, and a macOS notification bridge.

## Offscreen UI tests

Build Debug, then run the real-emulator smoke test with an APK:

```sh
python3 Scripts/run-ui-tests.py --app /path/to/Madroid.app --apk /path/to/app.apk --package com.example.app
```

For the volume controls alone, use `--test volume` instead of `--apk` and
`--package`. This checks mute, full volume, and midpoint volume through the
same native Android control path as Settings, then restores the previous level.

The launcher uses fresh guest data in `~/Library/Caches/madroid-ui-*`, reuses
Madroid's installed SDK and tools, and shuts down its own process afterward.
Windows stay hidden; input and resize commands use a private file queue.
The test checks rendered frames, guest resolution, display cleanup, and zero
visible windows. Screenshots and logs remain in the printed artifact directory.
Python Pillow is required for the frame check. The Debug-only mode disables
clipboard sharing and launcher creation, leaving the normal app session alone.

## License

MIT — see [LICENSE](LICENSE).
