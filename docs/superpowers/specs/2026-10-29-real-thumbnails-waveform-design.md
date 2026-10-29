# Real Timeline Thumbnails and Audio Waveform — Design

**Date:** 2026-10-29

## Goal
Replace synthetic timeline decoration with media-derived visuals that help users find cuts and see audio content. Use the existing bundled FFmpeg runtime; do not add a dependency.

## Current problem
Video strips are drawn by VideoStripPainter using repeated rectangles, and WaveformPainter synthesizes bars from sine/cosine functions. Neither reflects the imported media, so the timeline looks populated but conveys no editing information.

## User-visible behavior
- After importing video or opening a project, generate a cached strip of real video frame thumbnails in the background.
- Each visible video clip samples thumbnails based on its source-time range, including split/trimmed clips.
- While thumbnails are generating or unavailable, keep the existing visual placeholder so the editor stays responsive.
- After extracting/loading detached WAV audio, render a real waveform from that file.
- The visible waveform follows the current audio trim range by cropping the cached full-source waveform, rather than stretching the entire song into every trimmed clip.
- Cache output in the OS temporary directory keyed by media path, file size, and modified time. Failed/partial generations are not treated as valid cache entries.
- Reuse cached media visuals across project open/save sessions when source identity has not changed.
- Generation must not replace project state or stall playback. Results from an old media source must be ignored after switching files.

## Technical approach
- Extract up to 120 evenly spaced thumbnail JPGs for a video source, fixed 144x81 pixels, with FFmpeg fps, scale, and crop; calculate sample index from source-time ratio to support arbitrarily long videos.
- Generate a single 2400x60 PNG waveform per detached audio WAV using FFmpeg showwavespic.
- Keep generation asynchronous and separate from UI state transitions. Store output paths in ephemeral widget state, keyed to the active source/audio path.
- Use a pure-Dart helper to map source time to thumbnail array indices and test first/middle/last and invalid inputs.
- Keep all media asset files disposable; project files continue to store only media paths and edit state.

## Failure handling
- If FFmpeg fails or media has no decodable video/audio, keep the placeholder and show a concise status message.
- Delete incomplete cache products before retrying; only write a completion marker after at least one valid output file exists.
- If source changes while generation is running, do not display stale outputs for the new source.
- Never overwrite input media and do not block playback while generation runs.

## Non-goals
- Real-time decoded thumbnails, frame-accurate video preview, multi-source media bin, multiple tracks, waveform zoom independent of timeline zoom, and background worker/process cancellation. Those remain future milestones.

## Validation
- Unit tests cover thumbnail index mapping boundaries and invalid inputs.
- Widget tests verify the timeline still renders safely with no cached imagery and existing project controls remain usable.
- flutter analyze, all Flutter tests, Windows release build, bundled FFmpeg, Inno Setup, and artifact upload must pass on the current SHA before release.