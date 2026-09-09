# Phase 0 Spike Notes

Fill in each entry with the measurement, the command used, and the date.
Items marked **blocking** decide Phase 1–3 scope and must be answered before
Phase 1 starts. Environment for the spike: reference SDK at
`/Volumes/DATA/workspace/android` (emulator 36.3.10), AVD `Medium_Phone`
(API 36.1, Google Play, arm64).

| # | Question | Blocking | Result |
|---|---|---|---|
| 1 | `getDisplayConfigurations`: values of `maxDisplays` and `userConfigurable` at runtime | yes | _pending_ |
| 2 | Display flags: does 1225 give a bar-free display that accepts `am start --display`? Does 9? Does `1225 \| 16384` (OWN_FOCUS) behave differently? | yes | _pending_ |
| 3 | Mapping from emulator display index (1–3) to Android logical display id: `dumpsys display` fields available, is size a reliable join key? | yes | _pending_ |
| 4 | In-place resize: after `setDisplayConfigurations` with a new size for an existing id, does the Settings activity survive (config change) or restart / move to display 0? | yes | _pending_ |
| 5 | Focus nudge: does a `MouseEvent{buttons:0}` (or tap) to display 1 change `mTopFocusedDisplayId`, and do subsequent `sendKey` events land on display 1? | yes | _pending_ |
| 6 | MMAP transport: does `ImageTransport{channel: MMAP, handle: "file:///…"}` produce frames? Region byte layout, stride, header, tearing observed? | yes | _pending_ |
| 7 | Frame row order: top-down or bottom-up as the proto comment claims? | no | _pending_ |
| 8 | `injectWheel` on the phone image: scrolls, or silently dropped? | no | _pending_ |
| 9 | Boot times: cold boot vs quickboot snapshot restore (wall clock to `sys.boot_completed`) | no | _pending_ |
| 10 | Sustained fps and host CPU over gRPC at 720×1280, 1080×1920, 1080×2400 (RGBA8888, scrolling content) | no | _pending_ |
| 11 | Bootstrap without Java: emulator boots from a hand-written AVD (no `hw.device.name`/`hash2`) in an isolated SDK root with no `platforms/` directory? Any warnings? | yes | _pending_ |
| 12 | Quarantine: does a `URLSession`-downloaded emulator zip carry `com.apple.quarantine` after `ditto` extraction? Does the emulator launch and use HVF? | yes | _pending_ |
| 13 | Permission dialogs: does a runtime permission prompt from an app on display 1 appear on display 1 or display 0? | no | _pending_ |
| 14 | IME: with `show_ime_with_hard_keyboard 0` and injected keys, does the soft keyboard stay hidden on the secondary display? | no | _pending_ |
| 15 | Wheel/scroll and multitouch: pinch-zoom via two `Touch` identifiers works? | no | _pending_ |

## Commands and snippets

```bash
# Boot headless with gRPC
$ANDROID_HOME/emulator/emulator -avd Medium_Phone -grpc 8554 -qt-hide-window \
  -no-boot-anim -gpu host -feature Vulkan
adb wait-for-device shell 'while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 1; done'

# Display state on the Android side
adb shell dumpsys display | grep -E 'mDisplayId|uniqueId|DisplayDeviceInfo|mBaseDisplayInfo'
adb shell dumpsys window | grep -E 'mTopFocusedDisplayId|mFocusedWindow'
adb shell dumpsys activity activities | grep -E 'displayId|Task|Hist'

# Launch on a display
adb shell am start --display <id> -n com.android.settings/.Settings
adb shell cmd package resolve-activity --brief -c android.intent.category.LAUNCHER <pkg>

# Display-targeted key event (slow path)
adb shell input -d <id> keyevent KEYCODE_BACK
```

Record raw `dumpsys display` output before and after creating a display as a
fixture under `EmulatorKitTests/Fixtures/` once captured.
