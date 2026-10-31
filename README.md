# GifCut — desktop video editor MVP

GifCut is a Windows-first desktop video editor prototype built with Flutter.

## Included in this version

- Import a local video file.
- Video preview with play/pause and seeking controls, direct on-canvas resize/rotation handles, and black frames during empty timeline gaps.
- CapCut-inspired resizable docked layout: media bin, central preview, right-side inspector, and bottom timeline.
- Timeline clip selection, right-click context menu, split at playhead, trim start/end to playhead, duplicate, delete, and undo/redo history.
- MP4 export of the edited clip sequence using local FFmpeg.
- Timeline with video and audio tracks, timeline zoom, and a draggable playhead.
- Extract the video's audio to a WAV file.
- Project open/save/save-as in the .g3ficut format (Ctrl+O, Ctrl+S, Ctrl+Shift+S); Ctrl+Shift+O imports video.
- Desktop shortcuts for frame stepping, edit-point navigation, playback, split, ripple trim, duplicate, delete/ripple delete, export, project save/open, and undo/redo. Press F1 or use the keyboard icon to view the shortcut reference.
- Timeline clip dragging/reordering on the single video track, source-time versus sequence-time mapping, snapping control, and pointer-anchored timeline zoom.
- Windows installer with a Start menu entry and optional desktop shortcut.
- In-app checks for new stable versions published in GitHub Releases.
- Local processing; video is not uploaded to a server.

Project files store local media paths and edit state; the media itself stays on your computer. If a referenced file is moved or deleted, GifCut reports the missing path when opening the project.

## Not included yet

Multiple independent source assets and video/audio tracks, multi-select, autosave/recovery, media relinking, timed photo/title clips, keyframes, track mute/solo/lock, advanced effects, audio preview mixing, and advanced export profiles remain planned. G3fiCut is an early desktop editor and is not yet feature-equivalent to CapCut or Premiere Pro.

## Install and update

1. Download the installer named **G3fiCut-Setup-X.Y.Z.exe** from the repository's **Releases** page.
2. Run the installer and follow the prompts.
3. GifCut checks for a newer stable release on startup. You can also click the update icon in the title bar.
4. When you accept an update, GifCut downloads the published installer, verifies its SHA-256 digest from the GitHub Releases API, and launches the installer. Windows may request administrator permission.

Updates are published from semantic version tags. For example, push a tag named **v0.2.2** to trigger a Windows build and publish the installer to GitHub Releases. The built-in updater uses the public endpoint https://api.github.com/repos/G3fic/G3fiCut/releases/latest, so the repository must be public for unauthenticated clients to read release metadata and download assets.

## Publish a release

Create and push a tag on the commit to release:

    git tag v0.2.2
    git push origin v0.2.2

Use a new vMAJOR.MINOR.PATCH value for every release. GitHub Actions will analyze the Dart code, run tests, build the Windows application and installer, and attach the matching installer to the release. Check the Actions run before announcing the update.

## Build on GitHub

For pull requests and normal branch builds, GitHub Actions produces a downloadable installer artifact for testing. Open the Actions tab, select the latest successful **Build GifCut for Windows** run, and download the **G3fiCut-Windows-Installer** artifact.

For local development, install Flutter stable and Visual Studio with the **Desktop development with C++** workload. Run flutter pub get, then flutter run -d windows. For local audio extraction, put ffmpeg.exe in the app's executable folder or add FFmpeg to PATH.

## Technical notes

- Video preview uses media_kit / media_kit_video.
- Audio extraction runs FFmpeg as a local process and writes WAV files to Documents/GifCut/Media.
- The release workflow packages an FFmpeg LGPL Windows binary alongside the application. Review the upstream FFmpeg legal page and the included runtime notice before redistribution.
- The updater only reads public GitHub Releases and contains no GitHub access token.
