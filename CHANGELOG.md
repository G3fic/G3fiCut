# Changelog

## GifCut v0.3.80 — 2026-11-01

- Replace the old left tool rail with CapCut-style Media, Audio, Text, Stickers, Effects, Transitions, Captions and Filters categories.
- Add a media bin that imports multiple video, image and audio files and accepts Windows Explorer drag-and-drop; selected media can be sent to the editing timeline.
- Add editable timed text overlays, a dedicated text lane, right-side text settings, project persistence and FFmpeg export rendering.
- Replace effect/transition quick-apply controls with named thumbnail cards, animated source-frame previews, right-side duration settings and an explicit Add to timeline action.
- Keep the preview and export canvas black by default; blurred duplicate-video backgrounds are generated only when the dedicated option is enabled.
- Bump the app and Windows installer version to 0.3.80 and upgrade the project document schema to v4.

## GifCut v0.3.79 — 2026-11-01

- Make the preview canvas black by default instead of filling unused canvas space with a continuously blurred duplicate of the video.
- Add a separate preview-background blur toggle; the clip's own blur effect remains independent.
- Bump the Windows application and installer version to 0.3.79.


## GifCut v0.3.78 — 2026-10-31

- Add a larger library of FFmpeg crossfade transitions, including radial, diagonal, slice, wind, cover, reveal, squeeze and zoom variants.
- Add cinematic looks, VHS, RGB glitch, film grain, vignette, sharpening and five licensed 3D LUT presets.
- Bundle the five slaycamera LUTs in Windows releases with CC BY 4.0 attribution.
- Fill portrait and square canvases with a blurred copy of the video while keeping the full original frame visible; apply the same layout in exports.
- Use the same center-and-edge snapping system for video and photo layers, including rotation-aware object bounds and visible edge guides.

## GifCut v0.3.77 — 2026-10-31

- Save the verified Windows installer in the user's Downloads folder and open it through Windows Explorer so elevation prompts are shown correctly.
- Keep GifCut running until the installer takes over instead of exiting as soon as a child process is spawned; retain the downloaded setup file for manual launch if needed.

## GifCut v0.3.76 — 2026-10-31

- Fix in-app updates to launch the visible, SHA-256-verified Windows installer instead of silently copying files from a ZIP archive.
- Keep GifCut open if the installer cannot be started, and let Inno Setup handle administrator permissions and application replacement.

## GifCut v0.3.75 — 2026-10-31

- Restore the selected aspect ratio in the preview and use a dark-grey surround for letterboxed areas.
- Open contextual settings for selected video, photo, audio, effect, and transition items in the left inspector panel.
- Add photo import directly to the Media tab and place the inspector to the left of the preview.
- Expand transition choices and map them to FFmpeg xfade modes with editable type and duration.
- Avoid decoder seeks at contiguous split points to prevent a one-frame flash and brief audio dropout.
- Reduce the unused timeline label gutter and align all tracks closer to the left edge.


## GifCut v0.3.74 — 2026-10-31

- Fix the effect-placement regression test: the timeline correctly chooses the nearest available two-second gap, rather than incorrectly expecting no slot.
- Keep the numeric application version and Windows release build metadata in sync.

## GifCut v0.3.73 — 2026-10-31

- Place transition markers directly across video cuts and show them as translucent overlays on the video timeline.
- Allow effect blocks to be moved and resized from either edge without overlapping other effects.
- Pan the timeline only while holding the right mouse button; ordinary left-button dragging remains reserved for editing timeline items.
- Route Delete and Backspace to the currently selected timeline item instead of always deleting a video clip.
- Add animated hover previews to every built-in effect and transition.
- Keep the preview canvas fixed while changing the export aspect-ratio preset.
- Snap video rotation to 90-degree orientations when close to a right angle.
- Apply updates from a verified portable ZIP archive and restart GifCut without opening the Windows Setup wizard.
- Simplify the top bar by removing the update-check and keyboard-shortcut buttons.

## GifCut v0.3.72 — 2026-10-31

- Preserve the source video's aspect ratio when changing the preview frame, including during export.
- Zoom the timeline with the mouse wheel around the cursor position.
- Move standard effects and transitions into the Media panel's Effects tab; timeline lanes appear only after the first item is added.
- Apply the timeline snapping toggle to rotation-angle snapping and keep clip source ranges fixed while moving.
- Standardize the desktop application and installer branding as GifCut while retaining legacy installer asset names for existing installations.

## G3fiCut v0.3.68 — 2026-10-31

- Replace the video canvas pan recognizer with pointer-level drag tracking so media_kit gestures cannot cancel movement mid-drag.
- Ignore pointer input inside the rendered video texture while retaining drag input on the canvas surface.
- Add a regression widget test that sends several pointer moves while the draggable preview is moving underneath the pointer.


## G3fiCut v0.3.67 — 2026-10-31

- Restore direct on-canvas video transform controls with eight visible resize handles and a dedicated rotation handle.
- Remove video width, height and rotation sliders from the inspector; adjust the clip directly on the preview canvas.
- Make the media bin, preview inspector and timeline dock panels resizable with draggable dividers.
- Show a black preview during empty timeline gaps and keep playback moving through the gap before resuming the next clip.


## G3fiCut v0.3.66 — 2026-10-31

- Move primary editing actions from the horizontal toolbar into a vertical left tool rail.
- Remove independent width/height drag handles; use uniform video scaling and a dedicated bottom rotation handle.
- Reduce center-snap resistance so video and photo overlays can be freely positioned.
- Draw the extracted audio clip from measured PCM peak samples instead of a synthetic decorative waveform.
- Rebuild audio waveform when opening a project with an existing extracted WAV file.


## G3fiCut v0.3.65 — 2026-10-31

- Check GitHub Releases on startup, when the app returns to the foreground, and every six hours while open.
- Retry transient GitHub/network failures and show a clear status while preserving automatic retries.
- Keep installer downloads restricted to official GitHub Releases and verify SHA-256 before launch.


## G3fiCut v0.3.64 — 2026-10-31

- Fixed the widget-test analyzer failure by importing Flutter keyboard key definitions.
- Removed duplicate legacy timeline handlers so sequence-time seeking and edge trimming use one implementation.
- Kept the sequence-aware timeline editing, snapping, clip reordering, and gap-preserving export behavior.

## G3fiCut v0.3.63 — 2026-10-30

- Added sequence-aware timeline editing with separate source and sequence time.
- Added clip insert/reordering, snapping, pointer-anchored zoom, and sequence-aware export with preserved gaps.
- Added desktop editing shortcuts, frame stepping, edit-point navigation, and shortcut help.
- Improved FFmpeg export path handling and concat-list newline escaping.
- Retained project-file migration from schema v1 to schema v2.

## G3fiCut v0.3.0 — 2026-10-29

- Added versioned `.g3ficut` project files with open, save, and save-as controls.
- Restored video clip ranges, selected clip, detached audio range, zoom, and playhead from saved projects.
- Validated project schema and media files before replacing the active edit.
- Added protection against overwriting the active timeline with a failed media open.
- Made the timeline layout responsive to shorter windows.

## G3fiCut v0.2.7 — 2026-10-29

- Added undo and redo for video clip split, trim, duplicate, and delete operations.
- Added undo and redo for detached-audio extraction, trim, reset, and delete operations.
- Added Ctrl+Z, Ctrl+Y, and Ctrl+Shift+Z shortcuts and toolbar controls.
- Capped edit history at 100 states and clear it when a new source video is imported.
- Fixed the version fallback for local runs and standard CI builds so it follows pubspec.yaml.

## G3fiCut v0.2.2 — 2026-10-29

- Renamed the desktop application from ClipForge to G3fiCut.
- Updated the Windows installer, Start menu shortcuts, and installer filename.
- Updated the in-app updater to recognize and install G3fiCut releases.
- Preserved the existing application ID so existing installations can be upgraded.
- Existing functionality is unchanged: video preview, timeline controls, playback and WAV audio extraction remain available.

## GifCut v0.2.4

- Changed the application display name to GifCut.
- Applied the supplied blue jet/video icon to the Windows executable and installer.
