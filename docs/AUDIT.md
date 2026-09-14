# Project audit — 2026-09-14

Scope: handwritten Swift in Madroid and MadroidKit, unit tests, project.yml,
launch hooks, SDK bootstrap, guest Java helpers, generation, release,
and emulator test scripts. Generated protobuf bindings were checked by
regeneration; third-party dependency internals were not audited.

## Findings and fixes

| Area | Failure and correction | Verification |
| --- | --- | --- |
| Process exit timeout | A task-group timeout joined an uncancellable exit continuation, so shutdown never reached SIGKILL. The bounded wait now polls process state with cancellable sleeps. | Regression failed before the fix and passes afterward. |
| Subprocess cancellation | Cancellation before launch could miss the process; SIGTERM alone could leave a command running; failed launches left pipe readers blocked. Launch/cancel are synchronized, cancellation escalates, and failure closes writers. | Real subprocess input/output, pre-cancellation and ignored-SIGTERM tests; boot-failure cleanup test. |
| Startup/shutdown ownership | Quit during startup skipped cleanup because no session had been published. ADB could survive an emulator launch failure. Startup and shutdown tasks are tracked, startup is cancelled and joined, and partial resources are cleaned up. | Fake executable boot-failure and quit-during-startup tests; real emulator shutdown. |
| Remote shell arguments | Packages from launch URLs and other string arguments were interpolated into Android shell commands. All interpolated arguments in the ADB convenience methods and catalog lookup are now quoted. | Literal shell argument round-trip test with quotes, semicolons and substitutions. |
| Display rollback | Failed display discovery leaked a guest display; failed removal erased local ownership before the RPC succeeded. Discovery/resize roll back and removal commits ownership only after success. | Injected transport failure tests. |
| Parked window close | A parked window retained its former slot index; closing it could delete the replacement app's display. Close releases only a currently owned slot, with app-instance identity checks. | Real emulator parking/reuse/close regression. |
| Duplicate and stale window operations | Repeated launch requests could allocate several slots for one package. Repeated resume and completion after close could recreate unwanted windows. Pending operations are guarded, and closing cancels/checks pending work. | Repeated launch requests in emulator smoke test. |
| APK file-open handling | Opening an APK before Android was ready discarded the request, and install errors were swallowed. File-open requests now wait for readiness and report failures. The test stages APKs in its cache and waits for the installed package. | Real-emulator install check; initial smoke failure exposed missing diagnostics. |
| Download integrity | Resume accepted a 206 response starting at the wrong byte and downloads without a checksum could accept a body shorter than the expected size. Validate the range start and final byte count. | URLSession protocol fixtures for truncated bodies and wrong ranges. First-download promotion also passes; the suspected rename failure did not reproduce. |
| Clipboard | After host A → guest B, copying A again was suppressed forever as an old echo. Each accepted direction now clears the obsolete opposite-direction value. | Bidirectional A/B/A regression failed before the fix and passes afterward. |
| Launcher stubs | Equal app labels overwrote one another, and an unrelated bundle at the same path could be deleted. Names include package identity; unrelated files are preserved; script URLs are escaped. | Temporary-directory tests for duplicate labels, cleanup and unrelated files. |
| Screenshot transport | The 64 MiB message cap rejected large windows even though the display pool allowed up to 7680×7680. Both transport limits now accommodate the maximum supported RGBA frame. | Maximum-display transport budget regression. |
| Parsing/rendering | Truncated display output could index an empty array; malformed frame sizes could overflow or be accepted as complete. Both paths now reject invalid input. | Truncated output and invalid/overflowing dimension tests. |
| Background tasks | A finished old input stream could clear a replacement stream; old catalog refresh callbacks could replace current state after restart. Generation checks reject stale completions; refresh cancellation propagates. | Source review and build; emulator input smoke coverage. |
| Release/generation | Release builds used the external-volume DerivedData path explicitly prohibited by project guidance; protoc removed committed output before generation succeeded. Release uses default DerivedData, and generation stages output before replacing it. | Script syntax, Release build and generated-source comparison. Distribution signing/notarization was not executed. |

The offscreen harness now cleans up the app even if spawning the test fails or its shell ignores SIGTERM.
The guest Java sources were rebuilt with JDK 17 and D8 36.1.0, and the resulting
DEX bytes matched the bundled resource exactly.

## Repeatable checks

Run `Scripts/audit.sh` for script syntax, Debug build, unit tests, Release build
and generated-source comparison. Logs go to a printed temporary directory.
There is no configured Swift lint tool or hosted CI workflow in this checkout.

Add `--apk /path/to/app.apk --package com.example.app` to run the existing
hidden real-emulator harness with fresh guest data. It reuses the installed
SDK, verifies nonblank frames, input/resize dimensions, repeated launches,
parking/display ownership, native media volume, Settings visibility and shutdown.
It does not use the normal app's guest data. Native media volume has a separate `--test volume` mode.

Unit tests use fake executable/HTTP/display responses where appropriate;
those are distinguished above from actual emulator checks. Passing this audit
does not establish compatibility with every Android app, full first-run SDK
downloads on every mirror, or notarized distribution.

## Validation results

- `Scripts/audit.sh`: passed Debug build, 57 unit tests in 19 suites, Release
  build, shell/Python syntax checks, and protobuf regeneration comparison.
- Additional direct parser probe: an empty `real ,` dimension field is rejected
  without trapping.
- Real emulator: TapTap installed from a staged APK; three simultaneous launch
  requests produced one display; a nonblank 2560×1600 frame was rendered;
  rapid resizes reached the final frame/input dimensions. Closing parked TapTap
  left Settings on its reused display; closing Settings released that display.
- Native media volume: 0%, 100%, and 50% were applied and verified, then restored.
  Settings and all test windows remained hidden.
- The test app shut down successfully, and no processes associated with either
  isolated test root remained. The first test's installation failure is retained
  in the audit evidence; the staged-input rerun passed.
- Bundled guest DEX matched a rebuild from the Java sources. The Release app is
  arm64 and passed local code-signature verification. Distribution notarization
  and a live maximum-size screenshot were not tested.
- `git diff --check`: passed. Unrelated working-tree edits were preserved.
