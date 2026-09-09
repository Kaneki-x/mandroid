# Implementation Plan

Companion to [DESIGN.md](DESIGN.md). Phases are sequential; each has a
"done when" bar. Do not start Phase 1 until the Phase 0 measurements marked
**blocking** in [SPIKE-NOTES.md](SPIKE-NOTES.md) have answers.

## Phase 0 — Documentation, skeleton, spike

Goal: de-risk the design with measurements, not opinions, and stand up the
build scaffolding.

- [x] `docs/DESIGN.md`, `docs/PLAN.md`, `docs/SPIKE-NOTES.md`, `README.md`,
      `CLAUDE.md`, `LICENSE` (this branch)
- [ ] `project.yml` with `EmulatorKit`, `AndroidAppRunner`, `EmulatorKitTests`
      targets compiling empty
- [ ] `Protos/emulator_controller.proto` vendored from
      `<sdk>/emulator/lib/` with a `PROVENANCE` note (emulator version, date)
- [ ] `Tools/protoc-plugins/Package.swift` pinning `swift-protobuf` and
      `grpc-swift-protobuf`; `Scripts/gen-proto.sh` builds `protoc-gen-swift`
      and `protoc-gen-grpc-swift-2`, runs Homebrew `protoc`, writes
      `EmulatorKit/Generated/` (committed)
- [ ] `Tools/Spike/` — throwaway SwiftPM executable (AppKit window from a CLI
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
- [ ] Bootstrap dry run: parse the live manifests, download platform-tools
      and the emulator into a temporary SDK root, write an AVD by hand that
      points at the *local* system image, boot it with no Java on the path and
      no `platforms/` directory; record warnings and whether the quarantine
      attribute appears

Done when: `docs/SPIKE-NOTES.md` has every measurement filled in and the
skeleton project builds.

## Phase 1 — MVP: bootstrap, boot, one app in one window

EmulatorKit:
- [ ] `SDK/`: `SDKPaths`, `RepositoryManifest`, `Downloader` (resume,
      progress, SHA-1), `Unarchiver` (`ditto`), `SDKBootstrap` (idempotent
      plan), `AAPT2Fetcher`
- [ ] `AVD/`: `AVDConfig` (template in DESIGN §3.4), `AVDStore`
- [ ] `Emulator/`: `EmulatorProcess`, `EmulatorLaunchOptions`,
      `PortAllocator`, `BootWaiter`, `GuestSetup` (settings + snapshot)
- [ ] `ADB/`: `ADBClient`, `DumpsysDisplayParser`, `PackageListParser`
- [ ] `Client/`: `EmulatorConnection` (long-lived), `EmulatorClient` facade,
      `MethodConfig` raising `maxResponseMessageBytes` for `streamScreenshot`
- [ ] `Display/`: `DisplaySlotPool` (3 slots, unique sizes, no parking yet),
      `DisplaySlot`, `AppSession`
- [ ] `Frames/`: `Frame`, `FrameStream` protocol, `GRPCFrameStream`
- [ ] `Input/`: `InputChannel`, `CoordinateMapper`, `KeyMap`, `InputRouter`
      (single policy: nudge on activation)
- [ ] `Runner/`: `RunnerCoordinator`, `RunnerState`

App:
- [ ] `AppDelegate` (no quit on last window; URL scheme registered but only
      logs in this phase)
- [ ] `Setup/SetupWindow` (component list with sizes, license notice,
      progress, retry)
- [ ] `Library/LibraryWindow` (package names only), Open Play Store button
- [ ] `AppWindow/AppWindowController`, `FrameView` (CALayer + CGImage),
      `InputHandler`
- [ ] `Device/DeviceScreenWindowController` (display 0)

Tests: `RepositoryManifest` against the committed live manifests (channel
filtering, manifest-relative URLs, missing `host-arch` = universal,
per-manifest licenses, `<dependency>` min-revision), `AVDConfig`,
`DumpsysDisplayParser`, `PackageListParser`, `CoordinateMapper`, `KeyMap`.

Done when, starting from an empty Application Support folder: download → boot
→ Play Store opens in the device window → install an app → the app opens in
its own window with no bars → tap, drag, type, scroll work → ⌘W stops the app
and frees the display → Quit leaves no emulator process behind.

## Phase 2 — Multi-window, catalog, clipboard

- [ ] `DisplaySlotPool` LRU parking + `AppWindow/ParkedOverlayView`
- [ ] `Catalog/`: `InstalledApps`, `APKBadging`, `IconExtractor`
      (adaptive-icon fallback), `AppInstaller`, `AppCatalogCache`
- [ ] `Library/`: icons, search, drag-and-drop APK install, uninstall,
      "N of 3 windows in use"
- [ ] `Clipboard/ClipboardSync` with echo guard
- [ ] `Notifications/NotificationStream` (`TextViewFocus`) feeding
      `InputRouter`
- [ ] `WindowManager` (focus nudging, Window menu entries)
- [ ] `Menu/MainMenu`: Android menu (Back ⌘[, Home, Recents, Screenshot ⇧⌘S,
      Restart emulator, Show device screen), Edit menu forwarding
- [ ] `docs/compat.md` matrix: launches on a secondary display / survives
      resize / keyboard OK / notes (Play Integrity, `resizeableActivity`)

Tests: `DisplaySlotPool` LRU and acquire-while-full, `ClipboardSync` echo
suppression, aapt2 badging parser.

Done when: three apps run side by side; opening a fourth parks the LRU window
and it resumes on click; the library shows icons; copy and paste work both
ways without duplication; shortcuts work.

## Phase 3 — Native polish

- [ ] `Frames/MMAPFrameStream` (two regions) + `AppWindow/MetalFrameView`
      (`CAMetalLayer`, zero-copy blit, flip in the blit); display sized to
      physical pixels, dpi = 160 × backingScale
- [ ] `ResizeCoordinator`: free resize → 400 ms debounce → in-place display
      reconfiguration
- [ ] `Launchers/LauncherStubBuilder` + `URLSchemeHandler`
      (`~/Applications/Android Apps/<Label>.app`, `.icns` from the app icon,
      regenerate on catalog change, remove on uninstall)
- [ ] Global audio toggle (`streamAudio` is VM-wide)
- [ ] `Settings/`: system image choice and update, RAM/cores, default window
      size, cold boot, keep-warm policy, open logs, diagnostics
- [ ] Emulator crash detection and restart; pause frame streams for occluded
      or miniaturised windows; drop stale frames
- [ ] Release: hardened runtime, Developer ID signing, notarisation script

Done when: windows resize smoothly without losing app state, frames are
Retina-crisp, launcher stubs show up in Spotlight and the Dock, and the menu
bar exposes Android navigation with standard shortcuts.

## Future (not scheduled)

- Android-side display provider (prebuilt `scrcpy-server`, H.264 →
  VideoToolbox) to lift the 3-display cap and bandwidth ceiling
- Second emulator instance on demand
- `android-desktop` system image as plan B for compatibility
- Physical devices through the same provider abstraction

## Verification strategy

- **Unit tests** (`EmulatorKitTests`, run on every build): manifest parsing
  from fixture XML (archive selection by os/arch/channel), AVD config
  rendering, `dumpsys display` parsing from captured fixtures, package list
  parsing, aapt2 badging parsing, coordinate mapping (letterbox, scale,
  Retina edges), key mapping (modifiers, arrows, Return, Backspace,
  ⌘[ → `GoBack`), slot pool LRU, clipboard echo suppression.
- **Integration** (`Scripts/integration-test.sh`, requires a booted emulator,
  not run in CI): add and remove all three displays, verify id mapping, launch
  a known package on each, assert frames arrive with advancing `seq`, inject a
  tap and confirm a UI change via `uiautomator dump`, shut down and assert no
  orphan process.
- **Manual acceptance** per phase ("done when" above) and the compatibility
  matrix in `docs/compat.md`.
- **Gate before any push**: `xcodegen generate`, `xcodebuild -scheme
  AndroidAppRunner build`, `xcodebuild test -scheme AndroidAppRunner`, and
  `Scripts/gen-proto.sh` leaving a clean tree.
- **Git**: feature branches only; never commit on `main`.
