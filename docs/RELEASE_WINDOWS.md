# Windows release build on your own PC

GifCut can build and publish its Windows installer directly from a Windows 10/11 x64 computer. GitHub Actions is no longer responsible for creating the installer; it only runs Dart analysis and Flutter tests.

## Install once

1. **Git for Windows** — https://git-scm.com/download/win
2. **Flutter SDK 3.47.9** — use this exact version because it matches the validated project build. Add the Flutter `bin` directory to your PATH.
3. **Visual Studio 2022 Community** — in Visual Studio Installer, select the **Desktop development with C++** workload. Include the MSVC x64/x86 build tools and a Windows 10 or Windows 11 SDK.
4. **Inno Setup 6** — https://jrsoftware.org/isinfo.php
5. **GitHub CLI** — https://cli.github.com/ (only needed for one-command publication).

Open PowerShell and check the installations:

```powershell
flutter --version
flutter doctor -v
git --version
ISCC.exe /?
gh --version
```

Flutter should report **3.47.9**. In `flutter doctor -v`, Visual Studio must be detected without a Windows desktop toolchain error. If you only want to build an installer and upload it manually, GitHub CLI is optional.

## Get the project

Clone the repository once:

```powershell
git clone https://github.com/G3fic/G3fiCut.git
cd G3fiCut
```

Use the branch containing the changes you intend to release. Before publishing, make sure the latest code is committed and pushed to GitHub.

## Build an installer without publishing

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\release-windows.ps1
```

The script reads the version from `pubspec.yaml`, runs `flutter pub get`, `flutter analyze` and `flutter test`, builds the Windows app, downloads the LGPL FFmpeg runtime and the five attributed LUT presets, smoke-tests the required FFmpeg filters/effects/transitions, then creates the Inno Setup installer.

The output files are saved in `build\installer\`:

- `GifCut-Setup-X.Y.Z.exe` — the installer used by the in-app updater.
- `G3fiCut-Setup-X.Y.Z.exe` and `ClipForge-Setup-X.Y.Z.exe` — compatibility names for older installations.
- `GifCut-X.Y.Z-win-x64.zip` — portable app archive.

## Build and publish with one command

Sign in to GitHub CLI once:

```powershell
gh auth login
```

Choose GitHub.com, HTTPS, and authenticate in the browser with an account that has permission to publish releases in `G3fic/G3fiCut`.

For each release:

1. Update `version:` in `pubspec.yaml` to the next version, including a new build number, for example `0.3.81+89`.
2. Add the release notes to the top of `CHANGELOG.md`.
3. Commit and push the changes to the branch you want to release.
4. In the project folder, run:

```powershell
.\scripts\release-windows.ps1 -Publish
```

Publishing mode verifies that the working tree is clean, the current commit is already pushed to the matching `origin` branch, the version tag does not already exist, and GitHub CLI is authenticated. It then builds the installer and creates the matching GitHub Release with all four assets. The tag is created on the exact commit you built.

**Do not reuse a version.** If `v0.3.81` already exists, increment the version in `pubspec.yaml` before trying again.

## How in-app updates work

No updater code or installer naming convention is changed. GifCut continues to check:

`https://api.github.com/repos/G3fic/G3fiCut/releases/latest`

It looks for `GifCut-Setup-X.Y.Z.exe` first, then the legacy installer names. The local script uploads those names to the GitHub Release, so existing installations can discover the new version in the usual way.

## If a prerequisite is missing

The script stops and names the missing tool. Common fixes:

- **Flutter not found:** add the Flutter SDK's `bin` folder to PATH, close PowerShell, and open it again.
- **Wrong Flutter version:** install Flutter 3.47.9 and make sure that copy comes first in PATH.
- **Visual Studio not detected:** install the Visual Studio 2022 **Desktop development with C++** workload, then run `flutter doctor -v` again.
- **Inno Setup not found:** install Inno Setup 6, then reopen PowerShell.
- **GitHub publish is rejected:** run `gh auth status` and `gh auth login`; confirm the account has write access to the repository.
- **Git says the branch is not pushed:** commit and push the current changes, then rerun the command.

The script downloads FFmpeg and LUT files at build time, so an internet connection is required. The installer is built locally; GitHub Actions is not involved in packaging or publishing it.
