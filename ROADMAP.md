# GifCut Development Roadmap

This roadmap tracks real editing capabilities, not decorative controls. A feature is considered done only when its edit state, preview/export behavior, persistence (where applicable), and tests agree.

## 0.2.7 — Safe editing foundation
- [x] Split, trim, duplicate, and delete a video clip.
- [x] Extract source audio to a separate WAV clip and trim it independently.
- [x] Undo/redo video and detached-audio edits (released in v0.2.7).
- [x] Version-consistent CI build and v0.2.7 stable release.
- [x] Verify the v0.2.7 installer asset and successful release workflow.

## 0.3 — Project workflow and timeline manipulation
- [x] Separate source-media in/out points from sequence placement.
- [x] Duplicate clips as insert edits after the selected clip.
- [x] Drag-reorder clips on the single video track with snapping.
- [x] Frame stepping, edit-point navigation, focus-safe shortcuts, and shortcut help.
- [x] Project schema v2 with v1 timing migration.
- [x] Export clips in sequence order and preserve gaps with black segments.
- [ ] Stable clip IDs, multi-select, multi-track media, and cross-track editing.
- [ ] Complete audio preview mixing and multiple independent video/audio tracks.
- [x] Implemented in feature branch: versioned .g3ficut project format, open/save/save-as, media existence checks, clip ranges, selected clip, audio trim, zoom and playhead (release validation still pending).
- Autosave/recovery with clear handling of moved or missing media.
- [x] Media library with multiple video/image/audio imports, Windows Explorer drag-and-drop, and separate asset categories (v0.3.80; sequence editing is still single-source).
- Drag clips to move them on the timeline; move/insert without overlapping unexpectedly.
- Resizable trim handles, timeline snapping, ripple delete, copy/paste clips, and select multiple clips.
- [x] Effect and transition preset cards with real source-frame thumbnails and animated preview states; right-side settings and explicit timeline application (v0.3.80).

## 0.4 — Tracks and audio finishing
- Multiple video and audio tracks with track visibility, mute/solo, and locking.
- Clip volume, track volume, audio fade-in/fade-out, and fade curves.
- Audio/video unlink and relink; detach and replace source audio without unexpected sync drift.
- Per-clip transform and fit/fill controls for images/video.

## 0.5 — Text, captions, transitions, and basic effects
- [x] Basic timed text/title overlays with size and position controls, preview, project persistence, and FFmpeg export (v0.3.80).
- Extended text/title styling: font selection, color picker, alignment, outline/shadow, background, and keyframed animation.
- Subtitle import/export (SRT/VTT) and editable caption segments.
- [x] Named transition presets with animated preview, editable duration, per-cut placement, and FFmpeg xfade export (v0.3.80).
- Further transition modes and timing curves, including handles on the timeline.
- [x] Existing FFmpeg effects/filters and registered timeline effects are available through the new preset browser (v0.3.80).
- Extended parameterized effects, crop, color correction (brightness, contrast, saturation, temperature), and per-clip keyframes.
- Preview and export must use the same rendering graph.

## 0.6 — Motion and export controls
- Keyframes for position, scale, rotation, opacity, and audio volume.
- Speed changes with correct duration and audio handling.
- Export presets for resolution, frame rate, codec, quality/bitrate, audio codec/bitrate, and output container.
- Export progress, cancellation, validation of output path/storage, and a clear report on FFmpeg failures.

## 0.7 — Reliability, performance, and accessibility
- Background thumbnail/waveform generation and cancellable media jobs.
- Proxy/preview quality options for large files.
- Project migration tests for old project versions; recovery from invalid project files.
- Keyboard shortcut reference, focus traversal, accessible labels, and configurable shortcuts.
- Regression fixtures for variable frame rates, rotation metadata, missing audio, long timelines, and mixed resolutions.

## Release gate for every milestone
1. Run `flutter analyze` with no issues.
2. Run all unit and widget tests.
3. Build the Windows release and installer.
4. Check installer name/version, bundled FFmpeg and license notice, app icon, update metadata, and artifact contents.
5. Test a clean installation and in-place upgrade on Windows before calling the release stable.

## Explicit current limitations
G3fiCut is still an early editor, not yet feature-equivalent to mature editors. Multiple media sources on separate tracks, project save/load, real media thumbnails/waveforms, titles, transitions, effects, keyframes, and advanced export profiles are not implemented until their milestones above are completed.
