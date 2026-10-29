# Project Save/Load Implementation Plan

**Goal:** Add durable project persistence with validation so users can save the edit and resume later.

**Architecture:** A pure-Dart versioned ProjectDocument codec; UI-level file dialogs and player open/close; immutable document validated before applying. No new dependencies.

**Tech:** Flutter, Dart JSON, file_picker, flutter_test.

**Spec:** docs/superpowers/specs/2026-10-29-project-save-load-design.md

## Quality bar
- Unit tests cover round-trip, schema/format rejection, malformed fields, invalid time ranges, selected index, absent audio, and duration bounds.
- Save/open file dialogs use FileType.custom with allowedExtensions per File Picker docs.
- Opening a project with missing video or audio must leave current project data untouched.
- Canceled file pickers and canceled discard dialogs must not overwrite or change the current project.
- Ctrl+O opens projects; Ctrl+Shift+O imports video; Ctrl+S saves; Ctrl+Shift+S saves as.
- Run latest feature-branch Windows workflow, verify actual G3fiCut 0.3.0+8 version, and publish only when all CI steps pass.

## Task 1 — Tests first: project document codec
Files:
- Create test/project_document_test.dart
- Create lib/project_document.dart only after tests exist

Tests:
- Encode/decode roundtrip preserves video clips, selected index, audio range/path, zoom, and playhead.
- Unsupported schema version and unknown format fail with FormatException.
- Invalid/negative/non-finite clip times and invalid selected index fail.
- Video clip end exceeding a known duration fails.
- Missing audio path requires zero in/out points.
- Invalid zoom outside the supported range fails.

## Task 2 — Implement the pure-Dart project document
- Immutable data fields and copied immutable clip list.
- Strict fromJson/fromJsonString validation with consistent FormatException errors.
- Stable format identifier, schemaVersion, appVersion, and JSON encoding.

## Task 3 — Integrate Save/Open/Save As
Files:
- Modify lib/main.dart
- Modify test/widget_test.dart

- Add projectFilePath and projectDirty state.
- Capture current video/audio clips, path, durations, zoom, playhead, selection.
- Save writes a validated document using saveFile, FileType.custom, and .g3ficut extension.
- Open uses pickFiles with FileType.custom and .g3ficut; parse and validate before state mutation, and verify media existence.
- Open video through the existing player; only after it opens apply the stored timeline state and audio track.
- Add Save / Save As / Open toolbar controls.
- Add keyboard shortcuts and update the existing import-video shortcut to Ctrl+Shift+O.
- Mark project dirty on timeline edits, import, audio extraction, and zoom changes; do not mark dirty for playback/seeking alone.
- Before replacing dirty work, offer Save / Discard / Cancel. Cancel save or failed save aborts the replacement.
- Show a visible current project name and a dirty marker.

## Task 4 — Version and docs
- Bump pubspec version to 0.3.0+8 only after implementation is ready to test.
- Use the pubspec version fallback already added in .github/workflows/build.yml.
- Update README.md, CHANGELOG.md, ROADMAP.md.
- Add regression tests for empty project timeline and invalid file data.

## Task 5 — Verification and release
- Run flutter analyze and all Flutter tests.
- Verify Windows release, bundled FFmpeg, installer and uploaded artifacts.
- Inspect build logs for the exact G3FICUT_VERSION and installer filename.
- Open a pull request. Merge and publish only when the latest SHA passes the Windows workflow.
