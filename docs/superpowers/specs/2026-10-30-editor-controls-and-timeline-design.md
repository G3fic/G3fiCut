# Desktop Editor Controls and Timeline Model — Design Audit

**Date:** 2026-10-30  
**Repository:** G3fic/G3fiCut  
**Target:** Windows desktop editing workflow

## Goal

Make G3fiCut behave predictably like a desktop non-linear video editor: selection, transport, trim, split, duplicate, delete, snapping, timeline navigation, project persistence, and export must use consistent editing concepts. A visible command must do what its label and shortcut promise, and editing state must survive save/reopen.

## Current implementation findings

### P0 — Timeline model conflates source time and timeline position
TimelineClip.start/end currently serve as source in/out points and as the horizontal position on the timeline. Rendering uses left = clip.start * zoom; playback seeks directly to the same position; export concatenates ranges in list order.

Consequences:
- duplicateSelectedClip() copies the same start/end, so the duplicate draws on top of the original instead of appearing after it.
- There is no valid way to move/reorder a clip independently of the frames it references.
- Gaps, ripple edits, insert edits, and clip reordering cannot be represented cleanly.
- Playback playhead coordinates, source-media coordinates, and timeline coordinates are indistinguishable.

Required model: each clip needs a stable ID, source media ID, source in/out, timeline start, track ID, and per-clip properties. Timeline time must map to source time for preview and export. Same-track overlap rules and snapping must be explicit.

### P0 — Project files do not persist the complete edit state
Schema v1 stores only source paths, clip source ranges, selected clip, detached audio range, timeline zoom, and playhead. It omits photo overlays and transforms, video transform, aspect ratio, color settings, selected photo, motion blur, and transition settings.

Consequences: saving and reopening can silently discard visible work. New schema must be backward-compatible with v1 and include all persistent edit state.

### P1 — Keyboard control is sparse and inconsistent with desktop editors
Current map: Ctrl+Z/Y, Ctrl+O/S, Ctrl+Shift+O, Ctrl+E, Ctrl+B, Ctrl +/-; Delete/Backspace; Space; arrows jump five seconds; Home/End. Missing frame stepping, edit-point navigation, duplicate/export aliases, trim in/out shortcuts, and a discoverable shortcut reference. The app-wide Focus handler can also intercept keys before text input.

### P1 — Timeline interaction conventions are incomplete
- Clips can be selected, context-clicked, and edge-trimmed, but cannot be moved or reordered.
- There is no global snapping toggle or timeline snapping indicator for edit edges.
- Every vertical wheel event currently zooms the timeline, even without Ctrl, and zoom is not anchored around the pointer.
- No multi-select, copy/paste, ripple delete, track lock/mute/solo, or independent media clips.

### P1 — Preview, timeline and export state are not fully unified
Photo overlays are attached to the preview canvas and represented as full-width decorative photo rows, not timed clips. The detached audio track is represented separately but preview playback still uses the original source player. Transition and motion blur preview/export paths are not identical in all cases. Export does not expose progress or cancellation.

### P2 — Media/project workflow is still a single-source prototype
The media bin holds one video source, one detached audio file, and photo overlays. It is not yet a reusable multi-source bin with independently placeable audio/video assets. No autosave/recovery, relink workflow, proxies, or multi-track editing.

## Target interaction conventions

- Space: play/pause.
- Left/Right: step one source frame; Shift+Left/Right: one second.
- Ctrl+Left/Right: previous/next edit point.
- Home/End: start/end of sequence.
- J/K/L transport: reverse / pause / forward shuttle, with stable speed steps.
- Ctrl+Z / Ctrl+Y and Ctrl+Shift+Z: undo / redo.
- Ctrl+B and Ctrl+K: split at playhead.
- I / O: set selected clip start/end at playhead.
- Ctrl+D: duplicate selected clip as an insert after it.
- Delete: remove while leaving a gap; Shift+Delete: ripple delete.
- Ctrl+M: export.
- Ctrl+S / Ctrl+Shift+S: save / save as.
- Ctrl+mouse wheel: zoom timeline anchored under pointer; plain wheel: horizontal timeline navigation.
- Right-click a clip: context menu with the same actions as keyboard/toolbar.

Shortcuts must not consume text entry in editable controls. Unsupported commands must not be shown as available.

## Architecture direction

1. Introduce a timeline-domain model that separates timeline coordinates from source coordinates.
2. Keep media assets in a project bin; clips reference an asset instead of embedding one global video path.
3. Use one mapping layer for preview seeks, frame stepping, thumbnail placement, playback across cuts, and export segment ordering.
4. Store all persistent edits in a versioned project schema; provide a v1 -> v2 migration.
5. Make all commands go through named editor actions so keyboard, toolbar, context menu, and gestures share the same implementation.
6. Add domain tests first, then widget tests for discoverability and availability, then Windows CI.

## Non-goals for the first controls increment

Do not pretend to implement full NLE parity by adding decorative controls. The first increment improves reliable desktop keyboard and navigation behavior while the timeline-coordinate refactor is designed separately.
