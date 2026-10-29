# Project Save/Load — Design

**Date:** 2026-10-29

## Intent
Persist an editing session so users can close GifCut and return to the same timeline later. This is the next core editor capability after safe undo/redo.

## User-visible behavior
- **Открыть проект** reads a .g3ficut JSON project file.
- **Сохранить проект** overwrites the current project file, or prompts for a filename on first save.
- **Сохранить как…** chooses a new project path.
- Ctrl+O opens a project, Ctrl+S saves, Ctrl+Shift+S opens Save As, and Ctrl+Shift+O imports source video media.
- Timeline edits and imported/extracted media mark the project dirty. Playing/seeking does not mark the project dirty, but the playhead position is persisted whenever the project is saved.
- Before replacing a dirty project, the app asks whether to save changes, discard them, or cancel the operation. If Save fails or is canceled, the replacement operation is canceled.
- The app reports malformed, unsupported, or missing-media projects without pretending they loaded. Validation must complete before the editor swaps the current visible project state.
- Project data and media remain local; the app does not upload project files or media.

## Format
A versioned JSON document saved with extension .g3ficut:
- format: g3ficut-project
- schemaVersion: integer 1
- appVersion: semantic app version at save time
- videoPath, videoDurationMs, ordered videoClips source-time ranges, and selectedClipIndex
- optional audioPath, audioDurationMs, audioClipStart, and audioClipEnd
- timelineZoom and playheadMs

Media paths are stored as absolute local paths for this increment. Opening a project on another machine or after moving media will show a clear missing-file error; media relinking and relative-path packaging are explicitly deferred.

## Architecture
- Create a pure-Dart ProjectDocument/codec in lib/project_document.dart, with strict type/range validation and schema-version checks. This makes serialization independently unit-testable without launching Flutter or FFmpeg.
- Keep file dialogs and player lifecycle in _EditorPageState; build a validated document before mutating current state.
- Add toolbar actions and keyboard shortcuts. No new dependencies.

## Data integrity
- Reject unknown format or unsupported schema versions.
- Reject empty video paths, non-finite values, negative timestamps, reversed/zero-length video clip ranges, invalid selected index, zoom outside 12–80, and invalid audio boundaries.
- A clip range may not extend past the recorded source-video duration (when duration is known).
- Audio range is only valid when an audio path is present; if audio path is absent, audio in/out are zero.
- When opening, verify every referenced media file exists before changing the active project. If a media file is missing, keep the current project intact and report the path.
- Project writes should go to the user-selected path and report I/O errors; a canceled dialog is not a successful save.

## Non-goals for this increment
- Relative media paths, relinking missing media, bundling/copying media into a project folder, multiple sources/tracks, autosave/recovery, proxies, and asset packaging.
- This format is not yet a guarantee of backward/forward compatibility; future schema changes must add migration tests.

## Release gate
The project format tests, widget tests, flutter analyze, full flutter test, Windows release, installer packaging, and artifact upload must all pass before calling the milestone complete.
