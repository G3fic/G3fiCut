import 'package:flutter_test/flutter_test.dart';
import 'package:gifcut/editor_geometry.dart';

void main() {
  group('aspectRatioForPreset', () {
    test('returns the matching ratio for every preview preset', () {
      expect(aspectRatioForPreset('16:9'), 16 / 9);
      expect(aspectRatioForPreset('9:16'), 9 / 16);
      expect(aspectRatioForPreset('1:1'), 1);
      expect(aspectRatioForPreset('4:3'), 4 / 3);
      expect(aspectRatioForPreset('4:5'), 4 / 5);
      expect(aspectRatioForPreset('3:2'), 3 / 2);
    });

    test('falls back to landscape when a preset is unknown', () {
      expect(aspectRatioForPreset('unknown'), 16 / 9);
    });
  });
}
