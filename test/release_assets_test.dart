import 'package:flutter_test/flutter_test.dart';
import 'package:gifcut/release_assets.dart';

void main() {
  group('isNumericSemanticVersion', () {
    test('accepts numeric MAJOR.MINOR.PATCH versions', () {
      expect(isNumericSemanticVersion('0.3.72'), isTrue);
      expect(isNumericSemanticVersion('1.0.0'), isTrue);
    });

    test('rejects non-numeric or incomplete versions', () {
      expect(isNumericSemanticVersion('v0.3.72'), isFalse);
      expect(isNumericSemanticVersion('0.3'), isFalse);
      expect(isNumericSemanticVersion('0.3.72-beta'), isFalse);
      expect(isNumericSemanticVersion('GifCut 0.3.72'), isFalse);
    });
  });

  group('findReleaseInstallerAsset', () {
    test('prefers the current GifCut installer name', () {
      final asset = findReleaseInstallerAsset([
        {'name': 'G3fiCut-Setup-0.3.72.exe', 'id': 1},
        {'name': 'GifCut-Setup-0.3.72.exe', 'id': 2},
      ], '0.3.72');

      expect(asset?['id'], 2);
    });

    test('finds a legacy G3fiCut installer', () {
      final asset = findReleaseInstallerAsset([
        {'name': 'G3fiCut-Setup-0.3.71.exe', 'id': 7},
      ], '0.3.71');

      expect(asset?['id'], 7);
    });

    test('finds a legacy ClipForge installer', () {
      final asset = findReleaseInstallerAsset([
        {'name': 'ClipForge-Setup-0.3.70.exe', 'id': 9},
      ], '0.3.70');

      expect(asset?['id'], 9);
    });

    test('returns null for missing or non-numeric versions', () {
      expect(findReleaseInstallerAsset([], '0.3.72'), isNull);
      expect(
        findReleaseInstallerAsset([
          {'name': 'GifCut-Setup-0.3.72.exe'},
        ], 'v0.3.72'),
        isNull,
      );
    });
  });
}

  group('findReleaseAppArchiveAsset', () {
    test('finds the versioned portable Windows archive', () {
      final asset = findReleaseAppArchiveAsset([
        {'name': 'GifCut-0.3.72-win-x64.zip', 'id': 42},
        {'name': 'GifCut-Setup-0.3.72.exe', 'id': 43},
      ], '0.3.72');

      expect(asset?['id'], 42);
    });

    test('rejects missing or invalid app archives', () {
      expect(findReleaseAppArchiveAsset([], '0.3.72'), isNull);
      expect(
        findReleaseAppArchiveAsset([
          {'name': 'GifCut-0.3.72-win-x64.zip'},
        ], 'v0.3.72'),
        isNull,
      );
    });
  });

}
