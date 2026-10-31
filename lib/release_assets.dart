// Release-version and installer-asset helpers used by GifCut's updater.

/// Accepts the numeric MAJOR.MINOR.PATCH version format used by pubspec and
/// GitHub release tags after the optional leading "v" has been removed.
bool isNumericSemanticVersion(String version) =>
    RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version);

/// Finds the installer asset for a release, preferring the current GifCut name
/// while remaining compatible with older G3fiCut and ClipForge releases.
Map<String, dynamic>? findReleaseInstallerAsset(
  List<dynamic> assets,
  String version,
) {
  if (!isNumericSemanticVersion(version)) return null;

  final expectedNames = <String>[
    'GifCut-Setup-$version.exe',
    'G3fiCut-Setup-$version.exe',
    'ClipForge-Setup-$version.exe',
  ];

  for (final expectedName in expectedNames) {
    for (final asset in assets) {
      if (asset is Map<String, dynamic> && asset['name'] == expectedName) {
        return asset;
      }
    }
  }
  return null;
}
