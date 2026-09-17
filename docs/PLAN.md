# Implementation Plan

Companion to [DESIGN.md](DESIGN.md). Phases are sequential; each has a
"done when" bar. Do not start Phase 1 until the Phase 0 measurements marked
**blocking** in [SPIKE-NOTES.md](SPIKE-NOTES.md) have answers.

## Phase 0 — Documentation, skeleton, spike

Goal: de-risk the design with measurements, not opinions, and stand up the
build scaffolding.

- [x] `docs/DESIGN.md`, `docs/PLAN.md`, `docs/SPIKE-NOTES.md`, `README.md`,
      `CLAUDE.md`, `LICENSE` (this branch)
- [x] `project.yml` with `MandroidKit`, `Mandroid`, `MandroidKitTests`
      targets compiling empty
- [x] `Protos/emulator_controller.proto` vendored from
      `<sdk>/emulator/lib/` with a `PROVENANCE` note (emulator version, date)
- [x] `Tools/protoc-plugins/Package.swift` pinning `swift-protobuf` and
      `grpc-swift-protobuf`; `Scripts/gen-proto.sh` builds `protoc-gen-swift`
      and `protoc-gen-grpc-swift-2`, runs Homebrew `protoc`, writes
      `MandroidKit/Generated/` (committed)
- [x] `Tools/Spike/` — throwaway SwiftPM executable (AppKit window from a CLI
      via `NSApplication` + `setActivationPolicy(.regular)`) run against the
      local reference SDK and the existing `Medium_Phone` AVD:
      1. `emulator -avd Medium_Phone -grpc 8554 -qt-hide-window -no-boot-anim -gpu host`
      2. wait for adb + `sys.boot_completed`
      3. `getDisplayConfigurations` → record `maxDisplays`, `userConfigurable`
      4. `setDisplayConfigurations` adding display 1 at 840×1800 @ 320 dpi,
         flags 1225 (retry with 9, then `1225 | 16384`)
      5. map to the Android display id via `dumpsys display`
      6. `am start --display <id> -n com.android.settings/.Settings`
      7. `streamScreenshot(display: 1)` into a window (CGImage path)
      8. taps and drags as `TouchEvent` over `streamInputEvent`
      9. resize display 1 in place; does the Settings activity survive?
      10. focus nudge (`MouseEvent{buttons:0}`) then `sendKey`; where do keys
          land? (`dumpsys window | grep mTopFocusedDisplayId`)
      11. `injectWheel` on the phone image: honoured or dropped?
      12. `ImageTransport.MMAP` with a `file:///` handle: frames? byte layout?
      13. cold boot vs snapshot restore wall time
      14. sustained fps and host CPU at 720×1280, 1080×1920, 1080×2400 over gRPC
- [x] Bootstrap dry run: parse the live manifests, download platform-tools
      and the emulator into a temporary SDK root, write an AVD by hand that
      points at the *local* system image, boot it with no Java on the path and
      no `platforms/` directory; record warnings and whether the quarantine
      attribute appears

Done when: `docs/SPIKE-NOTES.md` has every measurement filled in and the
skeleton project builds.

## Phase 1 — MVP: bootstrap, boot, one app in one window

MandroidKit:
- [x] `SDK/`: `SDKPaths`, `RepositoryManifest`, `Downloader` (resume,
      progress, SHA-1), `Unarchiver` (`ditto`), `SDKBootstrap` (idempotent
      plan), `AAPT2Fetcher`
- [x] `AVD/`: `AVDConfig` (template in DESIGN §3.4), `AVDStore`
- [x] `Emulator/`: `EmulatorProcess`, `EmulatorLaunchOptions`,
      `PortAllocator`, `BootWaiter`, `GuestSetup` (guest settings)
- [x] `ADB/`: `ADBClient`, `DumpsysDisplayParser`, `PackageListParser`
- [x] `Client/`: `EmulatorConnection` (long-lived), `EmulatorClient` facade,
      `MethodConfig` raising `maxResponseMessageBytes` for `streamScreenshot`
- [x] `Display/`: `DisplaySlotPool` (3 slots, unique sizes, no parking yet),
      `DisplaySlot`, `AppSession`
- [x] `Frames/`: `Frame`, `FrameStream` protocol, `GRPCFrameStream`
- [x] `Input/`: `InputChannel`, `CoordinateMapper`, `KeyMap`, `InputRouter`
      (single policy: nudge on activation)
- [x] `Runner/`: `RunnerCoordinator`, `RunnerState`

App:
- [x] `AppDelegate` (no quit on last window; URL scheme registered but only
      logs in this phase)
- [x] `Setup/SetupWindow` (component list with sizes, license notice,
      progress, retry)
- [x] `Library/LibraryWindow` (package names only), Open Play Store button
- [x] `AppWindow/AppWindowController`, `FrameView` (CALayer + CGImage),
      `InputHandler`
- [x] `Device/DeviceScreenWindowController` (display 0)

Tests: `RepositoryManifest` against the committed live manifests (channel
filtering, manifest-relative URLs, missing `host-arch` = universal,
per-manifest licenses, `<dependency>` min-revision), `AVDConfig`,
`DumpsysDisplayParser`, `PackageListParser`, `CoordinateMapper`, `KeyMap`.

Done when, starting from an empty Application Support folder: download → boot
→ Play Store opens in the device window → install an app → the app opens in
its own window with no bars → tap, drag, type, scroll work → ⌘W stops the app
and frees the display → Quit leaves no emulator process behind.

**Status 2026-09-10: done.** `Scripts/integration-test.sh` passes (boot from
quickboot snapshot in ~23 s, open, click/type/scroll, in-place resize to
1400×960, close releases the display, quit leaves no processes). Also landed
early: free window resize with in-place display reconfiguration, Retina
sizing (dpi = 160 × backingScale), `mandroid://launch/<pkg>` URL
handling, debug automation hooks. Known gaps carried into Phase 2: package
names instead of labels/icons, no detection of an app that finished itself
(window shows black), no clipboard sync.

## Phase 2 — Multi-window, catalog, clipboard

- [x] `DisplaySlotPool` LRU parking + `AppWindow/ParkedOverlayView`
- [x] `Catalog/`: `InstalledApps`, `APKBadging`, `IconExtractor`
      (adaptive-icon fallback), `AppInstaller`, `AppCatalogCache`
- [x] `Library/`: icons, search, drag-and-drop APK install, uninstall,
      "N of 3 windows in use"
- [x] `Clipboard/ClipboardSync` with echo guard
- [ ] `Notifications/NotificationStream` (`TextViewFocus`) feeding
      `InputRouter`
- [x] `WindowManager` (focus nudging, Window menu entries)
- [x] `Menu/MainMenu`: Android menu (Back ⌘[, Home, Recents, Screenshot ⇧⌘S,
      Restart emulator, Show device screen), Edit menu forwarding
- [x] `docs/compat.md` matrix: launches on a secondary display / survives
      resize / keyboard OK / notes (Play Integrity, `resizeableActivity`)

Tests: `DisplaySlotPool` LRU and acquire-while-full, `ClipboardSync` echo
suppression, aapt2 badging parser.

Done when: three apps run side by side; opening a fourth parks the LRU window
and it resumes on click; the library shows icons; copy and paste work both
ways without duplication; shortcuts work.

**Status 2026-09-10: done except `NotificationStream`** (not needed: the
focus router tracks touches and `am start --display` moves focus reliably;
revisit if apps show a "keyboard not focused" state). Verified with four
installed apps: LRU parking and resume (task moves to display 0 and back),
labels and icons via aapt2 (raster, adaptive, obfuscated), ⌘V paste from the
Mac and ⌘C copy to the Mac, window auto-close when the app exits. Caveat
recorded in `docs/compat.md`: some apps lose text input after a park/resume.

## Phase 3 — Native polish

- [x] ~~`Frames/MMAPFrameStream`~~ dropped (spike: MMAP crashes the emulator;
      gRPC does 50 fps at 1080×2400). Retina sizing (display at physical
      pixels, dpi = 160 × backingScale) moves to Phase 1.
- [x] `ResizeCoordinator`: free resize → 400 ms debounce → in-place display
      reconfiguration
- [x] `Launchers/LauncherStubBuilder` + `URLSchemeHandler`
      (`~/Applications/Android Apps/<Label>.app`, `.icns` from the app icon,
      regenerate on catalog change, remove on uninstall)
- [x] Guest media-volume slider, including mute and persisted volume
- [x] `Settings/`: RAM/cores, graphics backend, device display profiles,
      default window size/orientation, launcher stubs, media volume, SDK
      download mirror, cold boot, and log/data folders
- [x] Optional KernelSU image preparation, activation status, and stock recovery
- [ ] System-image selection/update UI and configurable keep-warm policy
- [x] Emulator crash detection and restart; pause frame streams for occluded
      or miniaturised windows; drop stale frames
- [x] Release: hardened runtime, Developer ID signing, notarisation script

Done when: windows resize smoothly without losing app state, frames are
Retina-crisp, launcher stubs show up in Spotlight and the Dock, and the menu
bar exposes Android navigation with standard shortcuts.

**Status updated 2026-09-17: core native polish implemented.** Media volume
and mute use Android's native media stream and apply immediately. System-image
selection/update and configurable keep-warm policy remain outstanding.
Resize lives in
`AppWindowController` (debounced in-place reconfigure) rather than a separate
`ResizeCoordinator`. Launcher stubs verified: `~/Applications/Android
Apps/<Label>.app` is indexed by Spotlight and opens the app window. Settings
(⌘,) cover RAM/cores, default window height, stubs on/off, log and data
folders, restart and cold boot. Crash handling: an unexpected emulator exit
shows the error with "Try Again"; hidden or miniaturised windows stop
streaming frames. `Scripts/release.sh` signs, notarizes and staples.

## Settings and compatibility follow-up (2026-09-17)

- [x] Tablet, Phone, Compact phone, and bounded Custom device-screen profiles;
      apply changes by cold boot while preserving guest data. Separate app
      windows retain their own geometry.
- [x] KernelSU 3.3.0 ramdisk preparation for the tested Android 36.1 ARM64
      kernel; exact compatibility checks, pinned asset hashes, cancellable
      preparation, validated cache, and Manager initialization.
- [x] Stock → KernelSU → stock runtime checks with fresh guest writes preserved
      at both transitions and stock image hashes unchanged.
- [x] README icon uses the app's existing generated PNG.
- [ ] Exercise an uncached KernelSU asset download end to end. The runtime
      checks used verified cached release assets.

The 2026-09-17 audit passed Debug/Release builds, 85 tests in 26 suites,
script syntax checks, and generated-source verification. These are dated
results; rerun the audit for subsequent code changes. See
[KERNELSU.md](KERNELSU.md#validation) for the root-mode verification scope.

## Future (not scheduled)

- Android-side display provider (prebuilt `scrcpy-server`, H.264 →
  VideoToolbox) to lift the 3-display cap and bandwidth ceiling
- Second emulator instance on demand
- `android-desktop` system image as plan B for compatibility
- Physical devices through the same provider abstraction

## Verification strategy

- **Unit tests** (`MandroidKitTests`, run with `xcodebuild -scheme Mandroid test`): manifest parsing
  from fixture XML (archive selection by os/arch/channel), AVD config
  rendering, `dumpsys display` parsing from captured fixtures, package list
  parsing, aapt2 badging parsing, coordinate mapping (letterbox, scale,
  Retina edges), key mapping (modifiers, arrows, Return, Backspace,
  ⌘[ → `GoBack`), slot pool LRU, clipboard echo suppression.
- **Integration** (`Scripts/integration-test.sh`, boots the real emulator,
  not run in CI): launch with `-autoSetup`, wait for ready, open a package,
  assert one secondary display and a non-blank frame, click/type/scroll,
  resize and assert the in-place reconfiguration, ⌘[, close and assert the
  display is released, quit and assert no emulator or adb process remains.
  Drives the UI through `mandroid://debug/…` hooks (Debug builds only).
- **Fresh-install check** (manual, done 2026-09-10): `Mandroid -dataRoot
  <empty dir> -autoSetup YES` downloaded platform-tools, emulator 37.1.11 and
  the android-36.1 Play image from `dl.google.com` (about 7 min at 10 MB/s,
  resume verified after a kill mid-download), unpacked, first-booted in 40 s,
  rendered the device screen, installed an APK by drag and drop, fetched
  aapt2 for labels and opened an app window.
- **Manual acceptance** per phase ("done when" above) and the compatibility
  matrix in `docs/compat.md`.
- **Gate before any push**: `xcodegen generate`, `xcodebuild -scheme
  Mandroid build`, `xcodebuild test -scheme Mandroid`, and
  `Scripts/gen-proto.sh` leaving a clean tree.
- **Git**: feature branches only; never commit on `main`.
