# Timeline Undo/Redo and Version Reliability Implementation Plan

> **For agentic workers:** Use the inline Superpowers execution workflow. Execute each task in order; every behavior change uses test-first verification, and GitHub Actions is the authoritative Flutter/Windows build environment because this session has no local Flutter SDK.

**Goal:** Add reliable undo/redo for timeline edits and prevent local/test builds from using an obsolete application version.

**Architecture:** Implement an immutable pure-Dart timeline snapshot and bounded history stack, then adapt `_EditorPageState` edits to capture/restore snapshots. Keep current Flutter UI and FFmpeg pipeline; no new dependencies.

**Tech Stack:** Dart, Flutter, flutter_test, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-29-timeline-undo-redo-design.md`

## Global Constraints
- Flutter SDK: stable channel (the existing workflow).
- Dart SDK constraint: `>=3.3.0 <4.0.0`.
- No added package dependencies.
- Version in `pubspec.yaml`: `0.2.6+6` for the current published line; next feature release versioning is handled separately.
- Keep user-visible text in Russian.

## Review Focus
- Recording an edit where before and after snapshots are equal must not create a useless history item.
- Undo then making a new edit must clear the redo branch.
- History depth must be bounded without losing the newest states.
- Deleting and restoring detached audio must keep its path and trim range coherent.
- Importing another source must clear old timeline history.
- Ctrl+Shift+Z must redo while Ctrl+Z undoes; Ctrl+Y must also redo.
- Normal CI builds after a version bump must derive their version from pubspec rather than a stale constant.

---

### Task 1: Add a pure-Dart timeline history model

**Files:**
- Create: `lib/timeline_history.dart`
- Test: `test/timeline_history_test.dart`

**Interfaces:**
- `TimelineClipRange(start, end)`: immutable source-time range with `length`.
- `TimelineSnapshot(videoClips, selectedClipIndex, audioPath, audioClipStart, audioClipEnd)`: immutable snapshot with content comparison.
- `TimelineHistory(maxEntries: 100)`: `record(before:, after:)`, `undo(current)`, `redo(current)`, `clear()`, `canUndo`, `canRedo`.

- [ ] Write tests first for undo/redo, no-op recording, redo invalidation after a new edit, audio-range restoration, and maximum history depth.
- [ ] Commit tests to the feature branch and confirm they fail for the missing model.
- [ ] Implement only the minimum pure-Dart snapshot/history model.
- [ ] Run the history tests and full Flutter test suite through GitHub Actions; inspect logs, not just the run badge.

### Task 2: Integrate history into the editor

**Files:**
- Modify: `lib/main.dart`
- Modify: `test/widget_test.dart` if stable UI assertions are needed.

- [ ] Add capture/restore/record helpers in `_EditorPageState`.
- [ ] Route split, video trim, duplicate, delete, detached audio trim/reset/delete/add through history-aware updates.
- [ ] Clear history when a new video import starts.
- [ ] Add disabled/enabled Undo and Redo toolbar controls, Ctrl+Z, Ctrl+Y and Ctrl+Shift+Z.
- [ ] Ensure selection-only changes are not separate history entries and restored selection is clamped to the current clip list.
- [ ] Run `flutter analyze` and the entire `flutter test` suite via CI and inspect failures/logs.

### Task 3: Correct the version fallbacks

**Files:**
- Modify: `lib/main.dart`
- Modify: `.github/workflows/build.yml`

- [ ] Update the app's local `APP_VERSION` default to the current pubspec version.
- [ ] Derive the workflow's default build version from the `version:` field in `pubspec.yaml`; keep explicit release/tag overrides intact.
- [ ] Verify that a release-tag/commit build still sets the requested release version, and a regular branch build uses pubspec's version.

### Task 4: Document and verify

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

- [ ] Document keyboard shortcuts and the undo/redo scope and limitations.
- [ ] Run the latest branch workflow to completion; check Analyze Dart code, Run Flutter tests, Build Windows release, Build Windows installer, and uploaded artifacts.
- [ ] Review the diff and create a pull request; do not announce the change as release-ready until the Windows workflow succeeds.
