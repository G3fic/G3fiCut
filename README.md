# ClipForge — desktop video editor MVP

ClipForge is a Windows-first desktop video editor prototype built with Flutter.

## Included in this first version

- Import a local video file.
- Video preview with play/pause and seeking controls.
- A timeline containing a video track.
- Extract the video's audio to a WAV file.
- Automatically add the extracted audio as a separate audio clip **under the video track**.
- Timeline zoom and waveform-style visual representation.
- Local processing; video is not uploaded to a server.

## Not included yet

Trimming and splitting clips, multiple video/audio tracks, text and titles, transitions, effects, project saving, and final video export are planned for later iterations. The Export control is intentionally disabled in this MVP.

## Build on GitHub

GitHub Actions builds the Windows application and publishes a downloadable clipforge-windows artifact. It also packages an FFmpeg LGPL Windows binary alongside clipforge.exe.

1. Open the Actions tab in this repository.
2. Select **Build ClipForge for Windows**.
3. Open the latest successful workflow run.
4. Download the clipforge-windows artifact and extract the ZIP.
5. Start clipforge.exe from the extracted folder.

For local development, install Flutter stable and Visual Studio with the **Desktop development with C++** workload. Run flutter pub get, then flutter run -d windows. For local audio extraction, put ffmpeg.exe in the app's executable folder or add FFmpeg to PATH.

## Technical notes

- Video preview uses media_kit / media_kit_video.
- Audio extraction runs FFmpeg as a local process and writes WAV files to Documents/ClipForge/Media.
- FFmpeg is provided separately from the ClipForge Dart code. Review the upstream FFmpeg legal page and the included runtime notice before redistribution.
