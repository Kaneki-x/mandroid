# Android App Runner

Run Android apps on your Mac as if they were native macOS apps. Each Android
app gets its own window with a normal title bar, resizes like a Mac window,
shares the clipboard, answers to Cmd shortcuts, and shows up in the Dock and
Spotlight — no phone frame, no Android status or navigation bars.

**Status: design stage.** There is no runnable app yet. The design and the
phased plan live in [`docs/`](docs/):

- [docs/DESIGN.md](docs/DESIGN.md) — architecture, verified facts, mechanisms, risks
- [docs/PLAN.md](docs/PLAN.md) — phases with "done when" criteria
- [docs/SPIKE-NOTES.md](docs/SPIKE-NOTES.md) — open questions the first spike must answer

## How it works

The app downloads the stock Android Emulator, platform-tools and a Google Play
system image on first launch and boots the emulator headless. For every
Android app you open it creates a private virtual display inside the emulator,
launches the app on that display, and streams the display's pixels into a
macOS window over the emulator's gRPC API. Mouse, keyboard, scroll and
clipboard are translated back the same way.

## Requirements

- macOS 15 or later; Apple Silicon recommended (Intel is supported through the
  x64 emulator build)
- About 2.5 GB of disk for the emulator and system image, downloaded on first
  launch, plus space for Android apps and data
- No Java, Android Studio or SDK installation needed

## Limitations

- At most three Android app windows at a time per emulator instance (an
  emulator limit); additional windows are parked and resume on click
- Apps that require Play Integrity attestation (many banking and DRM apps)
  detect the emulator and will not run

## Roadmap

See [docs/PLAN.md](docs/PLAN.md). Phase 0 is a measurement spike; Phase 1 is
a single-window MVP; Phase 2 adds multi-window, the app library and clipboard
sync; Phase 3 adds Retina-crisp rendering, free resizing and per-app Dock
launchers.

## License

MIT — see [LICENSE](LICENSE).
