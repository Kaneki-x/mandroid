# Provenance

`emulator_controller.proto` is vendored verbatim from the Android Emulator
package `emulator/lib/emulator_controller.proto`:

- Emulator revision: 36.3.10 (build 14472402), `Pkg.Path=emulator`
- Copied: 2026-09-10
- Upstream: https://android.googlesource.com/platform/external/qemu/+/refs/heads/emu-master-dev/android/android-grpc/services/emulator-controller/proto/emulator_controller.proto

Re-copy from a newer emulator and re-run `Scripts/gen-proto.sh` when the
runtime API surface changes. Only `EmulatorController` is used; the other
services in the SDK (`snapshot_service`, `ui_controller_service`, …) are not
vendored.
