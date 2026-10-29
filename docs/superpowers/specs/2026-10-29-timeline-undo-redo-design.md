# Timeline Undo/Redo and Build Version Reliability — Design

**Date:** 2026-10-29

## Intent
Make editing safer by supporting undo and redo for timeline edits, including video clip split/trim/duplicate/delete and extracted-audio trim/reset/delete/add. A user should be able to recover from an accidental action without re-importing media. Also make test-build version labels follow `pubspec.yaml` so non-release builds do not silently advertise an obsolete version.

## Current state
The editor stores mutable `TimelineClip` ranges and detached-audio path/range directly in `_EditorPageState`. Edit handlers mutate these values in place and no history exists. The app has only a minimal widget test and a single large `lib/main.dart`. Release builds inject `APP_VERSION`, but the local default and the workflow's non-release fallback are hard-coded as 0.2.5 while `pubspec.yaml` is 0.2.6+6.

## Goals
- Add a bounded undo/redo stack (maximum 100 changes) with immutable snapshots.
- Undo/redo timeline video clip changes and detached audio clip add/trim/reset/delete.
- Expose buttons and keyboard shortcuts: Ctrl+Z undo, Ctrl+Y and Ctrl+Shift+Z redo.
- Clear history when importing a new video so edits from an old source cannot leak into a new project.
- Make non-release CI builds and local app version defaults read the current 0.2.6 version.
- Add direct unit tests for snapshot/history behavior and keep existing widget tests.

## Non-goals for this increment
- This does not yet add multiple video tracks, drag-and-drop clip movement, gaps, transitions, effects, titles/subtitles, project save/load, proxy media, or advanced export profiles. Those require separate designs and regression tests.

## Approaches considered
1. **Store full snapshots in the widget state.** Small initial diff, but mutable lists are easy to alias and difficult to unit-test.
2. **Create a small immutable timeline snapshot/history model (chosen).** Pure Dart, independently testable, no added dependencies; the widget converts its existing mutable timeline to/from snapshots.
3. **Adopt a full editor state-management framework.** Better for a much larger application but adds migration scope and dependencies before the editor has a project model.

Chosen approach: a pure-Dart model with immutable clip ranges and snapshots; UI integration remains incremental.

## Behavior
- A committed edit pushes its pre-edit snapshot only when the timeline state actually changes; it clears redo.
- Undo transfers the current snapshot to redo and restores the previous one; redo transfers the current snapshot to undo and restores the next one.
- History is capped at 100 undo states; adding beyond the cap drops the oldest state.
- Snapshot fields: ordered source-time video clip ranges, selected video clip index, detached audio path, detached audio in/out range.
- Selection-only changes, playback position, zoom, status messages, and export progress are not history entries.
- Importing a different video clears history; the opened source remains the project source for all clip ranges.

## Constraints and quality bar
- Windows desktop remains the first supported platform.
- No new dependencies.
- All user-facing changes remain in Russian.
- Every state transition added must have unit coverage where possible; CI must complete analyze, tests, Windows build, and installer packaging before the increment is called complete.
