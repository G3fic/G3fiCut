# GifCut v0.3.80 — desktop video editor MVP

GifCut is a Windows-first desktop video editor prototype built with Flutter.

## Included in this version

- Import multiple local video, image, and audio files into a searchable-style media library; add files through the picker or drag them directly from Windows File Explorer.
- Dedicated Media, Audio, Text, Stickers, Effects, Transitions, Captions, and Filters categories in a CapCut-style left workspace.
- Video preview with play/pause and seeking controls, direct on-canvas resize/rotation handles, and black frames during empty timeline gaps.
- CapCut-inspired resizable layout: tool categories, media/preset browser, central preview, right-side context inspector, and a full-width bottom timeline.
- Black preview and export canvas by default; blurred duplicate-video background is an explicit optional canvas setting. Clip blur remains independent.
- Effect and transition preset cards use real frames from the loaded source video, animate the preview on hover/selection, and open editable settings on the right before a separate Apply action.
- Editable text overlays with timing, font size, and position controls; text is visible in the preview and included in MP4 exports.
- Project schema v4 saves text overlays and all imported media paths.
- Timeline clip selection, right-click context menu, split at playhead, trim start/end to playhead, duplicate, delete, and undo/redo history.
- MP4 export of the edited clip sequence using local FFmpeg.
- Timeline with video, audio, photo, effect, transition, and text rows, timeline zoom, and a draggable playhead.
- Extract the video's audio to a WAV file.
- Project open/save/save-as in the .g3ficut format (Ctrl+O, Ctrl+S, Ctrl+Shift+S); Ctrl+Shift+O imports video.
- Desktop shortcuts for frame stepping, edit-point navigation, playback, split, ripple trim, duplicate, delete/ripple delete, export, project save/open, and undo/redo. Press F1 or use the keyboard icon to view the shortcut reference.
- Timeline clip dragging/reordering on the single video track, source-time versus sequence-time mapping, snapping control, and pointer-anchored timeline zoom.
- Windows installer with a Start menu entry and optional desktop shortcut.
- In-app checks for new stable versions published in GitHub Releases.
- Local processing; video is not uploaded to a server.

Project files store local media paths and edit state; the media itself stays on your computer. If a referenced file is moved or deleted, GifCut reports the missing path when opening the project.

## Not included yet

Multiple independent video sources on separate tracks, simultaneous multi-track audio mixing, timed photo clips with full project persistence, multi-select, autosave/recovery, media relinking, keyframes, track mute/solo/lock, advanced effect parameterization, and advanced export profiles remain planned. The current media library can hold multiple imported assets, but the editing sequence still uses one active source video and one audio lane. G3fiCut is an early desktop editor and is not yet feature-equivalent to CapCut or Premiere Pro.

## Install and update

1. Download the installer named **GifCut-Setup-X.Y.Z.exe** from the repository's **Releases** page.
2. Run the installer and follow the prompts.
3. GifCut checks for a newer stable release on startup. You can also click the update icon in the title bar.
4. When you accept an update, GifCut downloads the published installer, verifies its SHA-256 digest from the GitHub Releases API, and launches the installer. Windows may request administrator permission.
5. When upgrading from GifCut 0.3.75 or earlier, download and run the new installer manually once. Those older versions use the previous ZIP-based updater and cannot reliably install this updater fix. Future in-app updates launch the verified Windows installer directly.

The updater reads the public endpoint https://api.github.com/repos/G3fic/G3fiCut/releases/latest and downloads the versioned installer from that release. The repository must remain public so unauthenticated clients can read release metadata and download assets.

## Build and publish on Windows

The Windows installer is now built locally instead of by GitHub Actions. GitHub Actions only runs Flutter analysis and tests; it does not package or publish Windows installers.

See **[docs/RELEASE_WINDOWS.md](docs/RELEASE_WINDOWS.md)** for the one-time Windows setup and release instructions. Once Git, Flutter 3.47.9, Visual Studio 2022 with Desktop development for C++, Inno Setup 6, and GitHub CLI are installed and GitHub CLI is authenticated, publish a new release with:

    .\scripts\release-windows.ps1 -Publish

The script checks the project, builds the Windows app, downloads and verifies the FFmpeg runtime and licensed LUT presets, smoke-tests FFmpeg features, creates the installer and portable archive, then publishes the release to GitHub. It reads the semantic version from `pubspec.yaml` and refuses to publish uncommitted or unpushed changes or reuse an existing tag.

To create a local test installer without publishing, run:

    .\scripts\release-windows.ps1

Output files are saved in `build\installer\`. The in-app updater continues to use the existing GitHub Releases mechanism and the `GifCut-Setup-X.Y.Z.exe` asset name.

## Local development

Install Flutter 3.47.9 and Visual Studio 2022 with the **Desktop development with C++** workload. Run:

    flutter pub get
    flutter run -d windows

For local audio extraction during development, put `ffmpeg.exe` in the app's executable folder or add FFmpeg to PATH. The release script automatically bundles its own FFmpeg runtime with the installer.

## Technical notes

- Video preview uses media_kit / media_kit_video.
- Audio extraction runs FFmpeg as a local process and writes WAV files to Documents/GifCut/Media.
- The release script packages an FFmpeg LGPL Windows binary alongside the application. Review the upstream FFmpeg legal page and the included runtime notice before redistribution.
- Cinematic LUT presets are bundled from slaycamera/luts under CC BY 4.0 with attribution.
- The updater only reads public GitHub Releases and contains no GitHub access token.
