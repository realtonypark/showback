# Recording

`Sources/ShowbackCore/Recording.swift` owns capture and source-clock readiness. `Presentation.swift` owns the shared pointer timeline/drawing path. `MediaExport.swift` renders that timeline and narration into MP4.

- Capture the selected window unless the script explicitly selects a display. Never widen scope to recover from an error.
- Use actual point-to-pixel scale and a maximum 1,920-pixel edge. Preserve aspect ratio and fill the configured canvas.
- An independent agent-desktop overlay has no stable public recording identity. Showback owns its live/export drawing path and calls agent-desktop for actual UI actions.
- The first screen sample anchors the media timeline. Save pointer and narration offsets on that clock; do not use wall-clock time for synchronization.
- Display capture excludes Showback's presentation/control app. Create its windows before resolving the content filter.
- Preserve original video and narration. Advertise `demo.mp4` only after export completes and its duration is validated.
- An unexpected capture error must stop the presentation. Window resizing ends a window-scoped run rather than producing misaligned annotations.
- Source audio is generated narration. Microphone, system audio, camera, music, zoom editing, and uploads are outside this version.

Check `PresentationTests`, `MediaTests`, and real fixture recordings. Inspect video frames and streams. The synchronization target is 100 ms; record measured evidence in `docs/verification.md`.
