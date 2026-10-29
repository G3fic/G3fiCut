# Real Thumbnails and Audio Waveform Implementation Plan

**Goal:** Render actual source frames and waveform data on the timeline without slowing playback.

**Architecture:** Use cached FFmpeg-generated image files and a pure-Dart source-time-to-thumbnail mapper. UI uses asynchronous image widgets with the existing painted placeholder as fallback. No new dependencies.

**Spec:** docs/superpowers/specs/2026-10-29-real-thumbnails-waveform-design.md

## Task 1 — TDD thumbnail mapping helper
Files: lib/timeline_media_assets.dart, test/timeline_media_assets_test.dart
- [ ] Define thumbnailIndexForTime(timeSeconds, durationSeconds, thumbnailCount).
- [ ] Add tests for first/middle/last source times, negative and past-end times, empty thumbnails, zero/invalid duration, and non-finite inputs.
- [ ] Implement the mapper after tests are committed.

## Task 2 — Video frame extraction and cache
Files: lib/main.dart
- [ ] Add a cache directory keyed by media file path, size, and modified time.
- [ ] Extract at most 120 small frames with FFmpeg at a source-duration-adjusted frame rate.
- [ ] Cache only completed generations; remove partial output before retry.
- [ ] Generate after successful import/project open without setting busy.
- [ ] Guard against stale output after another video is opened.
- [ ] Render real frames per clip source-time interval using the mapping helper; retain placeholder fallback.

## Task 3 — Audio waveform extraction and trim-aware rendering
Files: lib/main.dart
- [ ] Create a full-source waveform PNG with FFmpeg showwavespic.
- [ ] Cache by audio file identity and retain the fake painter while unavailable.
- [ ] Crop the waveform image based on audioClipStart and audioClipEnd, so trim and visible content match.
- [ ] Trigger/refresh waveform generation on audio extraction, project open, and history restore.
- [ ] Ignore completion if the active audio path no longer matches the request.

## Task 4 — Version, docs, and verification
Files: pubspec.yaml, lib/main.dart, CHANGELOG.md, README.md, ROADMAP.md
- [ ] Prepare version 0.3.1+9 only after code passes initial checks.
- [ ] Add/review widget coverage for fallback UI.
- [ ] Run current SHA workflow; inspect logs for Analyze, Tests, Release, FFmpeg, Inno Setup and artifact upload.
- [ ] Create draft PR, require successful PR-head workflow, merge only when verified SHA matches, and publish the release.