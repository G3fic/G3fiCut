# Multi-media Project, Timeline and Compositor — Sub-project Specification

**Status:** Draft for approval  
**Parent:** [GifCut v0.3.79 Multimedia Editing Workspace](2026-11-01-editor-v0.3.79-design.md)

## Intent

Replace the single-source-video assumption with a persistent project model for independent video, image, audio and text assets and timeline items. Preview and export must resolve the same sequence.

## Goals

- Store multiple media assets with stable IDs, canonical local paths, media type, duration, dimensions/sample rate where known, and missing/relink state.
- Store ordered tracks and timeline items that reference assets by ID.
- Support video clips from different source files with source in/out and sequence position.
- Convert photo overlays into first-class image clips with duration, position, scale, rotation, opacity and z-order.
- Support independent audio clips with source trim, timeline start, gain and fade settings.
- Support text/title items with saved text and styling properties.
- Support effects over timeline intervals and transitions attached to valid adjacent video clip joins.
- Preserve v1-v3 project compatibility through a v4 migration without silently dropping existing edits.
- Implement undo/redo over canonical project edits.
- Match preview composition to export composition.

## Canonical model proposal

- `ProjectMediaAsset`: stable `id`, `path`, `kind`, optional media metadata and relink state.
- `ProjectTrack`: stable `id`, `kind`, `name`, mute/visibility/lock state and deterministic order.
- `ProjectTimelineItem`: stable `id`, `trackId`, `assetId` when applicable, sequence start, source in/out and type-specific settings.
- `ProjectTextItem`: text content and supported style/transform properties.
- `ProjectEffectClip` and `ProjectTransition`: retained as timeline annotations but validated against the canonical items and joins.
- `ProjectDocument`: schema v4, with explicit canvas background and export audio behavior.

The implementation may use separate sealed Dart types rather than one large nullable item type, provided IDs and serialization remain stable and the timeline/compositor interfaces remain deterministic.

## Preview / export

The preview resolver computes active items at a sequence time, sorts visual items by track order, resolves clip-local source time, and combines image/text/video layers. Audio preview mixes active audio clips and applies gain. FFmpeg export uses the same resolved item order and clip timing to construct input streams and filter graphs.

Text should be serialized as data and rendered to a transparent raster overlay for export, not interpolated unsafely into a shell command. Export must explicitly define what happens to each source clip's embedded audio when standalone audio tracks are present; avoid accidental duplication. Temporary intermediate files are cleaned on success, failure and cancellation.

## Migration contract

- Read all currently supported schema versions 1, 2 and 3.
- Map the legacy video source to a media asset and each existing video range to a video timeline item.
- Map the legacy extracted audio to an audio asset and audio timeline item preserving trim.
- Preserve timeline-scoped effects and transitions.
- New projects write schema v4 only.
- Missing source paths remain represented and are surfaced to the user; they are not removed during load.
- Legacy projects default to black canvas background, not automatic blurred video.

## Non-goals

- Cloud asset relinking, proxy generation, multicam editing, keyframe curves or professional DAW automation.
- Full subtitle editor or complex text animation.
- Hardware-accelerated composition beyond what the chosen Flutter/FFmpeg path supports.

## Acceptance

- Unit tests cover v1-v3 migration, v4 round trips, duplicate/missing paths, stable IDs, multiple sources, timing, z-order, clip trims, image/text/audio properties and validation failures.
- Timeline editing tests cover insert, move, trim, split where applicable, delete, snapping and undo/redo across track kinds.
- Widget tests cover selected item inspector behavior and black-by-default canvas with a separately persisted optional blur background.
- Export integration tests use short deterministic local assets to verify multiple video sources, image overlay, text overlay, audio mix, transition application and temporary-file cleanup.
- A project that fails to open because a source is missing still shows every saved item and identifies the missing path.

## Constraints

- Keep Flutter, media_kit and FFmpeg unless compatibility tests prove a specific blocker.
- All processing remains local.
- No source edit is allowed to discard legacy timeline state without a migration test.
