[CmdletBinding()]
param(
    [switch]$Publish
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Stop-WithMessage {
    param([string]$Message)
    throw $Message
}

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )

    Write-Host ""
    Write-Host "==> $Label" -ForegroundColor Cyan
    & $Command @Arguments
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        Stop-WithMessage "$Label failed with exit code $code."
    }
}

function Invoke-FfmpegSmokeTest {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    Write-Host "Checking FFmpeg: $Label"
    & $Executable @Arguments
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        Stop-WithMessage "FFmpeg smoke test failed: $Label (exit code $code)."
    }
}

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $projectRoot

$pubspecPath = Join-Path $projectRoot 'pubspec.yaml'
if (-not (Test-Path $pubspecPath)) {
    Stop-WithMessage "pubspec.yaml not found. Run this script from the GifCut repository."
}

$pubspec = Get-Content -Path $pubspecPath -Raw
$versionMatch = [regex]::Match($pubspec, '(?m)^version:\s*(\d+\.\d+\.\d+)(?:\+\d+)?\s*$')
if (-not $versionMatch.Success) {
    Stop-WithMessage 'Cannot read MAJOR.MINOR.PATCH version from pubspec.yaml.'
}
$version = $versionMatch.Groups[1].Value
$tag = "v$version"

Write-Host "GifCut local Windows release builder" -ForegroundColor Green
Write-Host "Version: $version"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Stop-WithMessage 'Flutter was not found in PATH. Install Flutter 3.47.9 and add its bin folder to PATH.'
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Stop-WithMessage 'Git was not found in PATH. Install Git for Windows first.'
}

$flutterVersionOutput = (& flutter --version 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) {
    Stop-WithMessage 'Could not run flutter --version. Check the Flutter installation.'
}
if ($flutterVersionOutput -notmatch 'Flutter\s+3\.47\.9') {
    Write-Host $flutterVersionOutput
    Stop-WithMessage 'This release script is pinned to Flutter 3.47.9, the version used by the validated project build. Install that version before building.'
}

$programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
$programFiles = [Environment]::GetEnvironmentVariable('ProgramFiles')
$innoCompiler = $null
if ($programFilesX86) {
    $candidate = Join-Path $programFilesX86 'Inno Setup 6\ISCC.exe'
    if (Test-Path $candidate) { $innoCompiler = $candidate }
}
if (-not $innoCompiler -and $programFiles) {
    $candidate = Join-Path $programFiles 'Inno Setup 6\ISCC.exe'
    if (Test-Path $candidate) { $innoCompiler = $candidate }
}
if (-not $innoCompiler) {
    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($command) { $innoCompiler = $command.Source }
}
if (-not $innoCompiler) {
    Stop-WithMessage 'Inno Setup 6 was not found. Install Inno Setup 6 and run this script again.'
}

$headSha = $null
if ($Publish) {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Stop-WithMessage 'GitHub CLI (gh) was not found. Install GitHub CLI, run gh auth login, then retry.'
    }

    $workingTree = (& git status --porcelain)
    if ($LASTEXITCODE -ne 0) { Stop-WithMessage 'Could not inspect the Git working tree.' }
    if ($workingTree) {
        Write-Host ($workingTree -join [Environment]::NewLine)
        Stop-WithMessage 'Commit and push all project changes before publishing. The publishing mode requires a clean working tree.'
    }

    $branchName = (& git branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branchName)) {
        Stop-WithMessage 'Publishing requires a checked-out Git branch (not a detached HEAD).'
    }

    $headSha = (& git rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($headSha)) {
        Stop-WithMessage 'Could not read the current Git commit.'
    }

    $remoteBranch = (& git ls-remote origin "refs/heads/$branchName")
    if ($LASTEXITCODE -ne 0 -or -not $remoteBranch) {
        Stop-WithMessage "Could not find origin/$branchName. Push the current branch to GitHub before publishing."
    }
    $remoteSha = ($remoteBranch -split '\s+')[0]
    if ($remoteSha -ne $headSha) {
        Stop-WithMessage "The current commit is not pushed to origin/$branchName. Push it to GitHub and run the release command again."
    }

    $localTag = (& git tag --list $tag)
    if ($localTag) { Stop-WithMessage "Tag $tag already exists locally. Increase the version in pubspec.yaml for the next release." }
    $remoteTag = (& git ls-remote --tags origin "refs/tags/$tag")
    if ($LASTEXITCODE -ne 0) { Stop-WithMessage "Could not check whether tag $tag already exists on GitHub." }
    if ($remoteTag) { Stop-WithMessage "Tag $tag already exists on GitHub. Increase the version in pubspec.yaml." }

    Invoke-CheckedCommand -Command 'gh' -Arguments @('auth', 'status') -Label 'Check GitHub CLI login'
}

Write-Host ""
Write-Host "==> Generate Windows Flutter project files" -ForegroundColor Cyan
Invoke-CheckedCommand -Command 'flutter' -Arguments @('create', '--no-pub', '--platforms=windows', '--project-name', 'gifcut', '.') -Label 'Generate Windows platform scaffolding'

$icon = Join-Path $projectRoot 'assets\gifcut.ico'
$iconTarget = Join-Path $projectRoot 'windows\runner\resources\app_icon.ico'
if (-not (Test-Path $icon)) { Stop-WithMessage "GifCut icon not found: $icon" }
$iconDirectory = Split-Path $iconTarget -Parent
if (-not (Test-Path $iconDirectory)) {
    New-Item -ItemType Directory -Path $iconDirectory -Force | Out-Null
}
Copy-Item -Path $icon -Destination $iconTarget -Force

Invoke-CheckedCommand -Command 'flutter' -Arguments @('pub', 'get') -Label 'Resolve Flutter dependencies'
Invoke-CheckedCommand -Command 'flutter' -Arguments @('analyze') -Label 'Analyze Dart code'
Invoke-CheckedCommand -Command 'flutter' -Arguments @('test') -Label 'Run Flutter tests'
Invoke-CheckedCommand -Command 'flutter' -Arguments @('build', 'windows', '--release', "--dart-define=APP_VERSION=$version") -Label "Build GifCut $version for Windows"

$releaseDirectory = Join-Path $projectRoot 'build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $releaseDirectory 'gifcut.exe'))) {
    Stop-WithMessage "Windows executable was not created: $releaseDirectory\gifcut.exe"
}

$tempDirectory = Join-Path $env:TEMP 'GifCut-release-build'
New-Item -ItemType Directory -Path $tempDirectory -Force | Out-Null

Write-Host ""
Write-Host "==> Download FFmpeg LGPL runtime" -ForegroundColor Cyan
$ffmpegArchive = Join-Path $tempDirectory 'ffmpeg-lgpl.zip'
$ffmpegExtract = Join-Path $tempDirectory 'ffmpeg-lgpl'
$ffmpegUrl = 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-lgpl.zip'
Invoke-WebRequest -Uri $ffmpegUrl -OutFile $ffmpegArchive -UseBasicParsing
if (Test-Path $ffmpegExtract) { Remove-Item $ffmpegExtract -Recurse -Force }
Expand-Archive -Path $ffmpegArchive -DestinationPath $ffmpegExtract -Force
$ffmpegItem = Get-ChildItem -Path $ffmpegExtract -Filter 'ffmpeg.exe' -Recurse | Select-Object -First 1
if ($null -eq $ffmpegItem) { Stop-WithMessage 'ffmpeg.exe was not found in the downloaded LGPL archive.' }
$ffmpegPath = Join-Path $releaseDirectory 'ffmpeg.exe'
Copy-Item -Path $ffmpegItem.FullName -Destination $ffmpegPath -Force

$ffmpegNotice = @(
    'GifCut bundles the FFmpeg LGPL build for Windows.'
    'Upstream project: https://ffmpeg.org/'
    'Binary provider: https://github.com/BtbN/FFmpeg-Builds'
    'FFmpeg source and licensing information: https://ffmpeg.org/legal.html'
    'Review the upstream FFmpeg license and build configuration before redistribution.'
) -join [Environment]::NewLine
Set-Content -Path (Join-Path $releaseDirectory 'FFmpeg-LICENSE-NOTICE.txt') -Value $ffmpegNotice -Encoding utf8

Write-Host ""
Write-Host "==> Verify required FFmpeg filters" -ForegroundColor Cyan
$filters = (& $ffmpegPath -hide_banner -filters 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) { Stop-WithMessage 'Could not read the FFmpeg filter list.' }
foreach ($filter in @('drawtext', 'xfade', 'lut3d', 'noise', 'chromashift', 'rgbashift', 'vignette', 'unsharp', 'colorchannelmixer', 'colorbalance', 'hue', 'lutrgb')) {
    if ($filters -notmatch "(?m)\b$filter\b") {
        Stop-WithMessage "The downloaded FFmpeg build does not include required filter: $filter"
    }
}
$xfadeHelpPath = Join-Path $tempDirectory 'xfade-help.txt'
& $ffmpegPath -hide_banner -h filter=xfade 2>&1 | Out-File -FilePath $xfadeHelpPath -Encoding utf8
if ($LASTEXITCODE -ne 0) { Stop-WithMessage 'Could not inspect the FFmpeg xfade filter.' }
$xfadeHelp = Get-Content -Path $xfadeHelpPath -Raw
foreach ($transition in @('circlecrop', 'radial', 'smoothleft', 'zoomin', 'coverleft', 'revealright')) {
    if ($xfadeHelp -notmatch "(?m)\b$transition\b") {
        Stop-WithMessage "The downloaded FFmpeg xfade filter is missing transition: $transition"
    }
}

Write-Host ""
Write-Host "==> Download licensed cinematic LUT presets" -ForegroundColor Cyan
$lutDirectory = Join-Path $releaseDirectory 'luts'
New-Item -ItemType Directory -Path $lutDirectory -Force | Out-Null
$lutBaseUrl = 'https://raw.githubusercontent.com/slaycamera/luts/a1709044efe115640dde1dee17d4185fc059af0d/luts'
$lutFiles = @(
    'slay-01-amber.cube',
    'slay-02-fade.cube',
    'slay-03-neon.cube',
    'slay-04-film.cube',
    'slay-05-portrait.cube'
)
foreach ($lutName in $lutFiles) {
    $destination = Join-Path $lutDirectory $lutName
    Invoke-WebRequest -Uri "$lutBaseUrl/$lutName" -OutFile $destination -UseBasicParsing
    if ((Get-Item $destination).Length -lt 900000) {
        Stop-WithMessage "Downloaded LUT file appears incomplete: $lutName"
    }
}
$lutAttribution = @(
    'Cinematic LUT presets by slaycamera'
    'Source: https://github.com/slaycamera/luts'
    'License: Creative Commons Attribution 4.0 International (CC BY 4.0)'
    'License text: https://creativecommons.org/licenses/by/4.0/'
    'Attribution: LUTs: slay (CC BY 4.0)'
    'The original LUT data is redistributed unchanged.'
) -join [Environment]::NewLine
Set-Content -Path (Join-Path $lutDirectory 'ATTRIBUTION.txt') -Value $lutAttribution -Encoding utf8

Write-Host ""
Write-Host "==> Smoke-test effects, text, canvas backgrounds and transitions" -ForegroundColor Cyan
$lut = (Join-Path $lutDirectory 'slay-04-film.cube') -replace '\\', '/'
$lut = $lut -replace ':', '\:'
$sampleFilters = @(
    "lut3d=file='$lut':interp=tetrahedral"
    'noise=alls=12:allf=t+u'
    'chromashift=cbh=3:crh=-3'
    'format=rgba,rgbashift=rh=5:rv=0:gh=-3:gv=1:bh=2:bv=-1'
    "lutrgb=r='clip((val-128)*1.12+128,0,255)':g='clip((val-128)*1.12+128,0,255)':b='clip((val-128)*1.12+128,0,255)',hue=s=0.92"
    'colorchannelmixer=aa=0.85,colorbalance=rs=-0.08:gs=0.01:bs=0.16'
    'vignette=angle=PI/5'
    'unsharp=5:5:1.1:5:5:0.0'
)
foreach ($sampleFilter in $sampleFilters) {
    Invoke-FfmpegSmokeTest -Executable $ffmpegPath -Label $sampleFilter -Arguments @('-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=64x64:rate=30', '-vf', $sampleFilter, '-frames:v', '1', '-f', 'null', 'NUL')
}

$blackCanvasGraph = '[0:v]scale=64:96:force_original_aspect_ratio=decrease,format=rgba,pad=64:96:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1,format=yuv420p[out]'
Invoke-FfmpegSmokeTest -Executable $ffmpegPath -Label 'black canvas composition' -Arguments @('-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=96x64:rate=30:duration=1', '-filter_complex', $blackCanvasGraph, '-map', '[out]', '-frames:v', '1', '-f', 'null', 'NUL')

$blurredCanvasGraph = "[0:v]split=2[fitSource][backdropSource];[backdropSource]scale=64:96:force_original_aspect_ratio=increase,crop=64:96,gblur=sigma=18,lutrgb=r='clip(val*0.62,0,255)':g='clip(val*0.62,0,255)':b='clip(val*0.62,0,255)',hue=s=0.82[backdrop];[fitSource]scale=64:96:force_original_aspect_ratio=decrease,format=rgba,pad=64:96:(ow-iw)/2:(oh-ih)/2:color=black@0,setsar=1[foreground];[backdrop][foreground]overlay=(W-w)/2:(H-h)/2:shortest=1,setsar=1,format=yuv420p[out]"
Invoke-FfmpegSmokeTest -Executable $ffmpegPath -Label 'optional blurred canvas composition' -Arguments @('-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=96x64:rate=30:duration=1', '-filter_complex', $blurredCanvasGraph, '-map', '[out]', '-frames:v', '1', '-f', 'null', 'NUL')

$textFile = Join-Path $tempDirectory 'gifcut-text-smoke.txt'
Set-Content -Path $textFile -Value "GifCut $version" -Encoding utf8
$textFileFilterPath = $textFile -replace '\\', '/' -replace ':', '\:'
$textGraph = "[0:v]drawtext=textfile='$textFileFilterPath':expansion=none:fontcolor=white:fontsize=12:x=(w-text_w)/2:y=(h-text_h)/2:enable='between(t,0,1)',format=yuv420p[out]"
Invoke-FfmpegSmokeTest -Executable $ffmpegPath -Label 'text overlay rendering' -Arguments @('-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=96x64:rate=30:duration=1', '-filter_complex', $textGraph, '-map', '[out]', '-frames:v', '1', '-f', 'null', 'NUL')

$transitionGraph = '[0:v]settb=AVTB,setpts=PTS-STARTPTS,fps=30,format=yuv420p[a];[1:v]settb=AVTB,setpts=PTS-STARTPTS,fps=30,format=yuv420p[b];[a][b]xfade=transition=radial:duration=0.3:offset=0.5[out]'
Invoke-FfmpegSmokeTest -Executable $ffmpegPath -Label 'radial xfade transition' -Arguments @('-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=64x64:rate=30:duration=1', '-f', 'lavfi', '-i', 'smptebars=size=64x64:rate=30:duration=1', '-filter_complex', $transitionGraph, '-map', '[out]', '-frames:v', '1', '-f', 'null', 'NUL')

Write-Host ""
Write-Host "==> Build Windows installer" -ForegroundColor Cyan
$installerDirectory = Join-Path $projectRoot 'build\installer'
New-Item -ItemType Directory -Path $installerDirectory -Force | Out-Null
$installerScript = Join-Path $projectRoot 'installer\ClipForge.iss'
Invoke-CheckedCommand -Command $innoCompiler -Arguments @("/DMyAppVersion=$version", $installerScript) -Label "Create GifCut-Setup-$version.exe"

$installer = Join-Path $installerDirectory "GifCut-Setup-$version.exe"
$legacyG3fiCutInstaller = Join-Path $installerDirectory "G3fiCut-Setup-$version.exe"
$legacyClipForgeInstaller = Join-Path $installerDirectory "ClipForge-Setup-$version.exe"
$portableArchive = Join-Path $installerDirectory "GifCut-$version-win-x64.zip"
if (-not (Test-Path $installer)) { Stop-WithMessage "Installer was not created: $installer" }
Copy-Item -Path $installer -Destination $legacyG3fiCutInstaller -Force
Copy-Item -Path $installer -Destination $legacyClipForgeInstaller -Force

Write-Host ""
Write-Host "==> Create portable ZIP package" -ForegroundColor Cyan
$portableExe = Join-Path $releaseDirectory 'gifcut.exe'
if (-not (Test-Path $portableExe)) { Stop-WithMessage 'gifcut.exe is missing from the Windows release folder.' }
if (Test-Path $portableArchive) { Remove-Item $portableArchive -Force }
Compress-Archive -Path (Join-Path $releaseDirectory '*') -DestinationPath $portableArchive -CompressionLevel Optimal
if (-not (Test-Path $portableArchive)) { Stop-WithMessage 'Portable ZIP archive was not created.' }

Write-Host ""
Write-Host "Build completed successfully." -ForegroundColor Green
Write-Host "Installer: $installer"
Write-Host "Portable:  $portableArchive"

if ($Publish) {
    Write-Host ""
    Write-Host "==> Publish GitHub Release $tag" -ForegroundColor Cyan
    Invoke-CheckedCommand -Command 'gh' -Arguments @(
        'release', 'create', $tag,
        $installer,
        $legacyG3fiCutInstaller,
        $legacyClipForgeInstaller,
        $portableArchive,
        '--repo', 'G3fic/G3fiCut',
        '--title', "GifCut $tag",
        '--generate-notes',
        '--target', $headSha
    ) -Label "Publish GifCut $tag to GitHub Releases"

    Invoke-CheckedCommand -Command 'gh' -Arguments @('release', 'view', $tag, '--repo', 'G3fic/G3fiCut') -Label 'Verify published GitHub Release'
    Write-Host ""
    Write-Host "Release published: https://github.com/G3fic/G3fiCut/releases/tag/$tag" -ForegroundColor Green
    Write-Host 'GifCut users can now detect this version using the existing in-app updater.'
}
else {
    Write-Host ""
    Write-Host 'Test build only. To publish after committing and pushing the current source, run:'
    Write-Host '  .\scripts\release-windows.ps1 -Publish' -ForegroundColor Yellow
}
