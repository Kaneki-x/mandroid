# App compatibility notes

Observed behaviour of apps running on a secondary emulator display inside an
Madroid window. Environment: emulator 37.1.11, Google Play
arm64 image API 36.1, display flags 1225. Update this table as apps are
tried; keep one line per app.

| App | Package | Launches in window | Survives resize | Keyboard | Notes |
|---|---|---|---|---|---|
| Shadowsocks 5.3.5 | `com.github.shadowsocks` | yes | yes (landscape relayout) | yes | After a park/resume cycle (task moved to display 0 and back) the search field stopped accepting input, even from `adb shell input text`; closing and reopening the window fixes it. |
| ProxyDroid 3.4.0 | `org.proxydroid` | yes | — | — | Icon comes from an obfuscated resource name (`res/M2.png`); label/icon extraction works. |
| Meow (Go) 0.3.4 | `io.github.madeye.meow.go` | yes | — | — | Adaptive icon resolved from the xxxhdpi raster. |
| BaoLianDeng 1.6.0 | `io.github.baoliandeng` | yes | — | — | `aapt2` lists a pseudo density 65534 pointing at mdpi; the catalog ignores it. |
| Settings (system) | `com.android.settings` | yes | yes | yes | Used for the spike; search typing verified. |
| Camera (AOSP) | `com.android.camera2` | yes | — | — | Runtime permission dialog appears on the app's own display. |

## Orientation

New windows open in landscape by default (Settings ▸ Windows switches to
portrait). Android ▸ Rotate Window (⌘R) swaps a window's width and height;
the virtual display is reconfigured in place, so the app relays out without
restarting. Android itself never reports a device rotation (the emulator
keeps rotation 0); apps see a configuration change, exactly as on a tablet
whose window was resized.

## General findings

- **Apps that finish themselves** (Back on the root activity) leave an empty
  display; the window watchdog closes the window a few seconds later.
- **Parking** moves the Android task to display 0, where it is visible in
  the Device Screen window until resumed. Some apps lose text-input focus
  after coming back; a reopen (⌘W, then open again) restores it.
- **Play Integrity / SafetyNet** protected apps (banking, some streaming)
  refuse to run on any emulator; this is not fixable from the runner.
- **`resizeableActivity=false`** apps are letterboxed by Android when the
  window aspect does not match; the runner does not compensate.
- **Notifications** appear in the device screen's status bar only; there is
  no macOS notification bridge yet.
- **Audio** plays through the emulator regardless of which window is
  focused (`streamAudio` is VM-wide).

## Audio

Android audio is played by the emulator's own CoreAudio backend, VM-wide.
That backend binds to the Mac's **default output device at the moment the
guest opens its audio stream** (in practice, at boot) and does not follow
later changes in System Settings ▸ Sound. If sound seems missing, check which
device was the default when Madroid started (a Bluetooth speaker or a
monitor's HDMI output are common surprises) and restart the emulator
(Android ▸ Restart) after switching outputs. The guest side can be checked
with `adb shell dumpsys audio` (player states) and the host side with
CoreAudio's per-process objects (the `qemu-system-aarch64` process shows
`runningOutput=1` while an app plays).
