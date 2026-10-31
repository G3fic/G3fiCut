# Effects and Transitions Library — Sub-project Specification

**Status:** Draft for approval  
**Parent:** [GifCut v0.3.79 Multimedia Editing Workspace](2026-11-01-editor-v0.3.79-design.md)

## Intent

Make effects, filters and transitions discoverable and usable through the visual card library shown in the supplied screenshot, and make their selected controls available in the right inspector.

## Goals

- Add separate left-dock categories for Effects, Transitions and Filters.
- Display catalogue items as a consistent grid of named cards.
- Each card contains an image thumbnail, not only a colored icon/rectangle. Prefer a frame from a loaded project asset; provide bundled local sample imagery when no project footage exists.
- Animate the preview on hover/focus/selection using the actual effect matrix/filter or actual transition behavior. Use a small sample preview and throttle animations when offscreen to avoid unnecessary GPU work.
- A click selects the card and shows its settings in the right inspector. Selection alone does not add anything to the timeline.
- Provide an explicit action in the inspector to add/apply the selection. For a transition, insertion is only enabled when a valid adjacent video cut is selected or can be selected.
- When a timeline effect/transition block is selected, the right inspector edits that existing item rather than the library preset.
- Provide controls for duration, intensity/strength where supported, enable/disable and preset-specific parameters.
- Export uses validated FFmpeg mappings and surfaces errors rather than silently replacing unsupported effects with a different one.

## Card behavior

- Cards have equal dimensions, a short title and a realistic 16:9 (or compact square) preview.
- Hover and keyboard focus play a muted looping demo; leaving the card stops it.
- Effects apply a color transform / blur / supported compositing operation to the preview image.
- Transitions show two sample frames and animate the actual transition class over the transition duration.
- When a user selects a card, preserve it as selected while the inspector is opened and avoid auto-inserting it.

## Right inspector contract

- Selected effect: name, category, preview, strength/duration controls where meaningful, enable switch, “Добавить на таймлайн”.
- Selected transition: name, transition type, duration, valid-cut selector or a clear “select two adjacent clips” state, “Добавить на стык”.
- Selected timeline block: editable block properties, remove action and existing undo/redo integration.
- Selected clip: show only relevant Video / Audio / Speed / Animation / Adjust controls. AI stylize remains hidden or clearly disabled until implemented.

## Background blur distinction

“Размытие фона” belongs to the preview canvas background settings, not to the clip's Blur effect. The canvas background defaults to black. Changing the clip blur must never enable the canvas background blur, and vice versa.

## Acceptance

- Catalogue tests assert every visible preset has a preview renderer and export mapping.
- Widget tests assert card click selects without adding, inspector updates, explicit Add inserts exactly one item, and invalid transition insertion shows an explanation without mutating the project.
- Animation tests verify the visible effect/transition preview uses the selected preset and stops when not active.
- Export tests confirm the saved effect/transition parameters reach the FFmpeg graph and that invalid FFmpeg filters report a useful error.
