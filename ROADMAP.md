# G3fiCut Development Roadmap

This roadmap tracks real editing capabilities, not decorative controls. A feature is considered done only when its edit state, preview/export behavior, persistence (where applicable), and tests agree.

## 0.2.7 — Safe editing foundation
- [x] Split, trim, duplicate, and delete a video clip.
- [x] Extract source audio to a separate WAV clip and trim it independently.
- [ ] Undo/redo video and detached-audio edits (current pull request).
- [ ] Version-consistent local builds, CI artifacts, and stable release.
- [ ] Validate that the installed release contains the same commit as the successful Windows workflow.

## 0.3 — Project workflow and timeline manipulation
- Project create/open/save using a versioned project document; store source file paths, clip ranges, track data, audio trim, zoom, and playhead.
- Autosave/recovery with clear handling of moved or missing media.
- Media bin with multiple source video/audio/image files.
- Drag clips to move them on the timeline; move/insert without overlapping unexpectedly.
- Resizable trim handles, timeline snapping, ripple delete, copy/paste clips, and select multiple clips.
- Accurate thumbnails and audio waveforms generated from the actual media rather than decorative placeholders.

## 0.4 — Tracks and audio finishing
- Multiple video and audio tracks with track visibility, mute/solo, and locking.
- Clip volume, track volume, audio fade-in/fade-out, and fade curves.
- Audio/video unlink and relink; detach and replace source audio without unexpected sync drift.
- Per-clip transform and fit/fill controls for images/video.

## 0.5 — Text, captions, transitions, and basic effects
- Text/title clips with font, size, color, alignment, outline/shadow, background, and duration.
- Subtitle import/export (SRT/VTT) and editable caption segments.
- Transitions such as dissolve, fade to/from black, and wipe with adjustable duration.
- Crop, rotate, scale, opacity, and basic color correction (brightness, contrast, saturation, temperature).
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
