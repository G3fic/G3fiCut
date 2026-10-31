# GifCut v0.3.80 — desktop video editor

GifCut is a Windows-first desktop video editor prototype built with Flutter.

## Included in this version

- Import a local video file, photos and audio from file picker or drag files from Windows Explorer directly into the editor.
- Import SRT/VTT captions with timecodes as individual text clips.
- Separate library tabs for Media, Audio, Text, Stickers, Effects, Transitions, Captions and Filters.
- Central video preview with play/pause and seeking controls, direct on-canvas resize/rotation handles for video and drag-positioning for photo/text overlays.
- Black preview/export canvas by default, with an explicit separate toggle for blurred background fill.
- Timed photo and text/title overlays with dedicated timeline lanes, inspector styling and project save/open support.
- Project schema v4 with automatic migration from project formats v1–v3.
- Effect and transition cards with animated hover samples; selecting a card opens its inspector, and a separate button inserts it on the timeline.
- Resizable docked layout: media library on the left, preview in the center, inspector on the right, and bottom timeline.
- Timeline clip selection, split, trim, duplicate, delete, undo/redo, zoom and snapping.
- MP4 export using local FFmpeg.
- In-app checks for new stable versions published in GitHub Releases.
- Local processing; video and media files are not uploaded to a server.

Project files store local media paths and edit state; the media itself stays on your computer. If a referenced file is moved or deleted, GifCut reports the missing path when opening the project.

## Not included yet

Multiple independent source video assets in one sequence, multiple independent audio tracks, fully featured multi-track video editing, track mute/solo/lock, audio preview mixing, keyframes, autosave/recovery, media relinking, multi-select and advanced export profiles remain planned. GifCut is an early desktop editor and is not yet feature-equivalent to CapCut or Premiere Pro.

## Install and update

1. Download the installer named **GifCut-Setup-X.Y.Z.exe** from the repository's **Releases** page.
2. Run the installer and follow the prompts.
3. GifCut checks for a newer stable release on startup. You can also click the update icon in the title bar.
4. When you accept an update, GifCut downloads the published installer, verifies its SHA-256 digest from the GitHub Releases API, and launches the installer. Windows may request administrator permission.

Updates are published from semantic version tags. The built-in updater uses the public endpoint https://api.github.com/repos/G3fic/G3fiCut/releases/latest.

## Build on GitHub

For pull requests and normal branch builds, GitHub Actions produces a downloadable installer artifact for testing. Open the Actions tab, select the latest successful **Build GifCut for Windows** run, and download the **GifCut-Windows-Installer** artifact.

For local development, install Flutter stable and Visual Studio with the **Desktop development with C++** workload. Run `flutter pub get`, then `flutter run -d windows`. For local audio extraction, put `ffmpeg.exe` in the app's executable folder or add FFmpeg to PATH.

## Technical notes

- Video preview uses media_kit / media_kit_video.
- Audio extraction and video composition run FFmpeg as local processes.
- The Windows release workflow bundles the LGPL FFmpeg runtime and verifies the filters needed by export, including `drawtext`.
