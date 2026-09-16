# Native UI polish validation

Branch: `feature/native-ui-polish`. Checked on 2026-09-15 with the macOS 15
deployment target and the local macOS SDK. No dependencies or persisted
settings formats changed.

## Build and source checks

`Scripts/audit.sh` passed using default DerivedData: Debug and Release builds,
74 tests in 24 suites, script syntax, and generated protobuf source comparison.
`git diff --check` passed. The existing `ipv4(host:port:)` deprecation warning
in `EmulatorConnection.swift` is unrelated to this presentation change.

Audit logs: `/var/folders/1z/507v_ftj4sd4vl1s515ycj340000gn/T/mandroid-audit.Kq0LGJ`.

## Visual checks

100 offscreen PNGs and eight contact sheets are retained under
`~/Library/Caches/mandroid-ui-polish-review/`. `render.py` and `Gallery.swift`
in that folder reproduce the presentation fixtures against the Debug framework.
The renderer copies the production views and substitutes fixture state only;
it does not change the production coordinator or write user settings.

Inspected light/dark and minimum/default variants of:

- Library empty state, long names, no search results, and labeled APK drop target.
- Running/paused tile labels and symbols.
- Setup component summary, download progress, boot stage, and a wrapping error.
- Settings pending-restart notice and scrollable grouped controls.
- Proxy validation error and disabled controls while saving.
- Native paused/resuming overlays.

Setup's primary action stays visible when the component list needs scrolling.
Long tile names truncate to two lines, with the full name and package retained
in help and the full name exposed to accessibility. Running/paused indicators
use text and symbols, not color alone.

The fixture harness checks Return activation on the actual AppKit overlay,
rejecting repeated activation while resuming, and allowing retry after failure.
It also checks the shared SwiftUI animation helper returns no animation for
Reduce Motion. Reduced-motion screenshots inject the preference into fixture
copies; they do not change the user's macOS preference.

## Runtime coverage and limits

The unmodified `Scripts/run-ui-tests.py --test smoke` passed with TapTap:
APK installation, duplicate open handling, rendered guest frames, input and
rapid resize geometry, parking/slot reuse, closing, and its built-in volume
checks (0%, 100%, 50%) plus Settings. No test windows became visible.
Artifacts: `~/Library/Caches/mandroid-ui-1l7a_lp0/artifacts/`.

An earlier attempt during the Release build hit the smoke script's fixed
8-second opening wait; cleanup cancelled the still-pending display acquisition.
The same unmodified test passed after the build finished. The failed attempt
is retained at `~/Library/Caches/mandroid-ui-g1v45njv/`; the timing explanation
is an inference, not a reproduced emulator defect.

The separate volume run also passed, followed by an additional real Android
Settings park/resume cycle. Session allocation and the active title returned,
and screenshots were captured before and after resume. The runner shut down
cleanly. Its original volume script plus the extra checks are retained in
`~/Library/Caches/mandroid-ui-polish-review/runtime/`; results are under
`~/Library/Caches/mandroid-ui-9x23gcey/artifacts/`.

The offscreen renderer does not exercise VoiceOver speech, a visible window's
Tab-focus traversal, mouse double-click/context-menu interaction, the native
APK file picker or Finder drag delivery. Those handlers were retained or
reviewed in source, but need an interactive acceptance pass. Proxy error/saving
screens are fixtures; they do not demonstrate a live proxy save. The unit
suite covers proxy parsing/persistence and existing settings contracts.

The host is newer than macOS 15; deployment-target compilation does not replace
a run on macOS 15. System preference changes during an in-flight animation were
not exercised. AppKit rotation reads Reduce Motion for each rotation; the
paused overlay is removed synchronously after successful resume.
