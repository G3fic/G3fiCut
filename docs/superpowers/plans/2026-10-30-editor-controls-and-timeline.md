# Editor Controls and Timeline Model — Implementation Plan

> Execute incrementally on main. Each functional change must have tests and CI evidence. Do not claim a feature is complete just because a control is visible.

**Goal:** Standardize G3fiCut desktop controls and then replace the prototype timeline with a real source-time/timeline-time model.

**Design:** docs/superpowers/specs/2026-10-30-editor-controls-and-timeline-design.md

## Phase 1 — Reliable desktop command handling
- [ ] Keep keyboard commands from intercepting text entry.
- [ ] Add frame-accurate left/right stepping using the current video's FPS metadata.
- [ ] Add Shift+Arrow one-second navigation and Ctrl+Arrow edit-point navigation.
- [ ] Add Ctrl+K split alias, Ctrl+D duplicate, Ctrl+M export, I/O trim, and a shortcut help dialog.
- [ ] Add keyboard tests for frame step, modifiers, and command guards.
- [ ] Make mouse-wheel navigation predictable: Ctrl+wheel zooms around the pointer; plain wheel moves horizontally.
- [ ] Add a snapping toggle and apply snap thresholds to timeline edge trims.

## Phase 2 — Correct clip placement semantics
- [ ] Add stable IDs and separate sourceIn/sourceOut from timelineStart.
- [ ] Implement time mapping between sequence time and source time.
- [ ] Fix split, trim, move, reorder, duplicate, insert, gap delete, and ripple delete.
- [ ] Add clip drag/drop and edge snapping.
- [ ] Add multiple source assets and multiple video/audio tracks.
- [ ] Update history snapshots to include placement, selection, track state, and edit metadata.
- [ ] Add pure-Dart domain tests before changing UI/export.

## Phase 3 — Complete project persistence
- [ ] Add schema v2 for media assets, clip IDs/placements, overlays, transform, aspect ratio, effects, transitions, and audio state.
- [ ] Migrate schema v1 projects without data loss.
- [ ] Add missing-media relink flow and safe failure behavior.

## Phase 4 — One render graph for preview and export
- [ ] Represent timed photos/titles/effects as timeline clips.
- [ ] Use the same normalized render graph for preview and FFmpeg export.
- [ ] Ensure detached audio is audible in preview and correctly aligned in export.
- [ ] Add cancellation, progress, export presets, and output validation.
- [ ] Add regression fixtures for mixed frame rates, missing audio, rotations, and long timelines.

## Release gate
1. flutter analyze has no issues.
2. All unit and widget tests pass.
3. Windows release and installer build succeed.
4. Release asset name/version and SHA-256 metadata match the package.
5. Update flow points to the exact stable release.
6. Only then call the increment complete.
