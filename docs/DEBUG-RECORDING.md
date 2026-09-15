# Debug window recording

Debug builds accept these `mandroid://debug/` commands:

- `record?secs=30&fps=15&file=/tmp/mandroid.mp4`: record to an H.264 MP4.
- `stoprecord`: finalize the current recording early. Starting another recording
  also finalizes the previous one before opening the new output.
- `screenperm`: request macOS Screen Recording permission for Mandroid.
- `move?pkg=device&x=100&y=900`: position a window by its top-left corner.
- `front?pkg=device`: bring a window forward. Use an Android package ID instead
  of `device` to target an app window.
- `library`: open the library.

With Screen Recording permission, recording uses ScreenCaptureKit to capture
Mandroid windows on the main display, with audio and cursor capture enabled.
`all=1` includes the entire display. Without permission, or with `composite=1`,
it renders the app's visible window layers over a synthetic backdrop; this mode
has no audio or cursor and may not reproduce every system-drawn window detail.
`scale=1` controls the composite output size relative to the screen's point size.
Screen capture uses its own output resolution and ignores `scale`.

Duration must be finite and within `(0, 3600]` seconds, FPS within `1...120`,
and scale within `(0, 4]`. Existing output files are replaced. URL-encode paths
containing spaces or query delimiters. Completion or failure is written to
`logs/app.log` in the app's data root. Quitting the app finalizes active recording.
These commands are absent from Release builds.

Run `python3 Scripts/recording-test.py --app /path/to/Debug/Mandroid.app`
with `ffprobe` installed to verify composite recording, repeated stop, replacement,
invalid input, and quit finalization. It uses a temporary data root and hidden app
windows. It checks MP4 encoding and lifecycle, not window appearance, live Android
content, or permission-dependent ScreenCaptureKit recording.
