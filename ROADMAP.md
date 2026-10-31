# G3fiCut — CapCut-class desktop editor roadmap

This roadmap defines a staged effort to turn G3fiCut from an early single-source editor into a capable, local-first, multi-track desktop editor inspired by the workflow and breadth of CapCut.

A feature is complete only when its edit state, real-time preview, deterministic export, project persistence, undo/redo where applicable, and automated regression coverage agree. A tab or placeholder control is not an implementation.

## Product target and boundaries

- Windows-first desktop editor with a CapCut-like workspace: media/library navigation, preview canvas, contextual inspector, and multi-track timeline.
- Local-first processing; core editing does not upload media.
- Broad parity for core desktop workflows: media management, multi-track editing, audio, titles/captions, transitions, effects, color, motion/keyframes, speed, and export.
- Cloud-only services (account sync, online marketplace, licensed music catalog, social publishing, collaboration, and proprietary AI services) are outside the initial parity target. Local/open alternatives may be added where licensing and reliability permit.
- Preserve compatibility with existing .g3ficut projects and installed releases.

## Stage 0 — Engineering foundation and editor architecture
- [ ] Split the large editor widget into workspace, media bin, preview, inspector, timeline, transport, dialogs, and export modules.
- [ ] Introduce stable IDs for media assets, tracks, clips, effects, transitions, and keyframes.
- [ ] Replace index-based selection with ID-based selection and a command-based edit model.
- [ ] Add schema migrations, relative media references, relinking, missing-media resolution, autosave, and crash recovery.
- [ ] Make undo/redo cover all user-visible edits through reversible commands.
- [ ] Add integration fixtures and deterministic render/export tests.
**Exit criteria:** old projects open without loss; full edits survive save/reopen; undo/redo and recovery are tested.

## Stage 1 — Media library and project organization
- [ ] Import multiple video, audio, image, GIF, and still-image formats.
- [ ] Bins/folders, search, sorting, metadata, duration, resolution, frame rate, and file size.
- [ ] Real thumbnails, filmstrips, audio waveforms, cancellable background jobs.
- [ ] Proxy generation and relinking for moved/offline files.
- [ ] Drag media from the library to any compatible track.
- [ ] Voiceover capture where supported.
**Exit criteria:** large mixed-media bins do not block the UI; assets survive restart and can be relinked.

## Stage 2 — Professional multi-track timeline
- [ ] Multiple video, overlay, audio, title, caption, and effect tracks.
- [ ] Stable clip IDs, multi-select, range selection, copy/paste, duplicate, grouping, linked audio/video.
- [ ] Insert, overwrite, ripple, roll, slip, slide, split, trim, and ripple-delete edits.
- [ ] Resizable track headers/heights; mute, solo, lock, visibility, reorder, and track targeting.
- [ ] Snapping to playhead, clip edges, markers, and keyframes; magnetic/ripple modes.
- [ ] Markers, in/out range, zoom-to-fit, scrolling, and frame-accurate navigation.
- [ ] Nested sequences/compound clips after the base engine is stable.
**Exit criteria:** overlapping clips render in correct stacking order; operations are undoable and frame-accurate.

## Stage 3 — Audio editing and mixing
- [ ] Real-time multi-track audio playback/mixing and per-clip/per-track gain.
- [ ] Volume keyframes, fades, pan/balance, mute/solo, and meters.
- [ ] Detach, relink, replace, and synchronize source audio/video.
- [ ] Voiceover recording, noise reduction, normalization, and audio ducking.
- [ ] EQ, compressor, limiter, reverb, delay, and plugin support if feasible.
- [ ] Beat/tempo markers and waveform editing.
**Exit criteria:** preview and exported mix match within documented tolerances; no long-form sync drift.

## Stage 4 — Text, captions, stickers, and graphics
- [ ] Editable text clips: font, size, weight, spacing, alignment, fill, outline, shadow, background, and position.
- [ ] Text presets and reusable local templates.
- [ ] SRT/VTT import/export, caption segmentation, styling, timing, and speaker labels.
- [ ] Animated text and sticker/image overlays with transform controls.
- [ ] Shape, solid-color, gradient, and transparent overlay layers.
**Exit criteria:** titles/captions remain editable after reopening and render consistently.

## Stage 5 — Transitions, effects, and compositing
- [ ] Real transitions: dissolve, fade, wipe, slide, zoom, adjustable duration and curve.
- [ ] Reorderable video-effect stacks with parameters and per-clip/global scope.
- [ ] Crop, mask, chroma key, blur, sharpen, vignette, glow, and blend modes.
- [ ] Adjustment layers and reusable effect presets.
- [ ] Correct compositing/alpha across multiple tracks and shared preview/export render graph.
- [ ] Preview quality controls and reliable GPU acceleration where available.
**Exit criteria:** effects/transitions persist and match between preview and export.

## Stage 6 — Color correction and grading
- [ ] Exposure, brightness, contrast, highlights, shadows, whites, blacks, saturation, temperature, tint, and vibrance.
- [ ] Curves, color wheels, HSL controls, and LUT import/application.
- [ ] Before/after comparison, scopes where feasible, and copy/paste/reset grading.
- [ ] Documented color management and HDR format support.
**Exit criteria:** shared preview/export color pipeline with image-based regression tests.

## Stage 7 — Motion, keyframes, speed, and reframing
- [ ] Keyframes for position, scale, rotation, opacity, crop, effect parameters, and audio volume.
- [ ] Linear, hold, and Bezier easing with editable curves.
- [ ] Speed changes, reverse, freeze frame, and speed ramps with correct sequence duration.
- [ ] Optical-flow interpolation where feasible, with graceful fallback.
- [ ] Preview transform handles, anchor/pivot controls, fit/fill, and aspect-ratio reframing.
- [ ] Stabilization and motion tracking after the render graph is reliable.
**Exit criteria:** animated values evaluate at arbitrary timestamps and survive save/reopen/export.

## Stage 8 — Export and delivery
- [ ] MP4/MOV profiles, codecs (H.264/H.265/AV1 where available), resolution, frame rate, bitrate/quality, audio codec, and sample rate.
- [ ] Hardware encoder detection with software fallback.
- [ ] Export range, queue, progress, pause/cancel, estimated size, and useful diagnostics.
- [ ] Landscape, portrait, square, and platform-oriented presets.
- [ ] Batch export and still-frame export.
- [ ] Validate path, free space, codec availability, and output integrity.
**Exit criteria:** reproducible presets; safe cancellation; output decodes and matches project duration.

## Stage 9 — Usability, reliability, and release quality
- [ ] Match the supplied CapCut reference layout and responsive panel behavior.
- [ ] Customizable shortcuts, tooltips, accessible labels, localization, and focus handling.
- [ ] Cache, proxy quality, preview quality, autosave, and hardware-acceleration settings.
- [ ] Performance tests: long timelines, many tracks, high-resolution/VFR media, rotation metadata, and missing streams.
- [ ] Crash-safe recovery and diagnostics export.
- [ ] Clean-install and in-place-upgrade validation for each stable Windows release.
**Exit criteria:** no known data-loss issues; tests pass; Windows installer verified on a clean environment.

## Release gate for every milestone
1. `flutter analyze` has no issues.
2. Unit, widget, and integration tests pass.
3. Preview and FFmpeg export are checked against the same timeline fixture.
4. Save/reopen, migration, recovery, and undo/redo are tested for affected features.
5. Windows build and installer are verified before a stable release is announced.

## Current baseline (v0.3.64)
- [x] Single-source video preview and playback.
- [x] Basic single-video-track split, trim, duplicate, delete, reorder, snapping, and undo/redo.
- [x] Basic detached-audio extraction and WAV export.
- [x] Project open/save with schema v2 and sequence-aware clip timing.
- [x] Basic FFmpeg sequence export and GitHub Releases updater.
- [ ] All stages above remain planned or partial until their end-to-end exit criteria are met.
