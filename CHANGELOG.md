# Changelog

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
