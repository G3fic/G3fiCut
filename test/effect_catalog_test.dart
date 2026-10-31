import 'package:flutter_test/flutter_test.dart';
import 'package:gifcut/effect_catalog.dart';
import 'package:gifcut/project_document.dart';

void main() {
  group('Built-in transitions', () {
    test('every supported transition maps to a non-empty FFmpeg xfade name', () {
      expect(ProjectTransition.supportedTypes, builtinTransitionFilters.keys.toSet());
      expect(builtinTransitionFilters.length, greaterThanOrEqualTo(58));
      expect(builtinTransitionFilters.values.toSet(), hasLength(58));
      for (final entry in builtinTransitionFilters.entries) {
        expect(entry.key, isNotEmpty);
        expect(entry.value, isNotEmpty);
        expect(RegExp(r'^[a-z]+$').hasMatch(entry.value), isTrue);
      }
    });

    test('unknown transition uses a safe fallback', () {
      expect(transitionFilterName('unknown'), 'fadeblack');
    });
  });

  group('Built-in effects', () {
    test('all timeline effect types are registered', () {
      expect(ProjectEffectClip.supportedTypes, builtinEffectTypes);
      expect(builtinEffectTypes.length, greaterThanOrEqualTo(20));
    });

    test('all bundled LUT presets have preview matrices and files', () {
      expect(builtinLutFiles.keys, lutPreviewMatrices.keys);
      expect(builtinLutFiles.length, 5);
      for (final entry in builtinLutFiles.entries) {
        expect(entry.value.endsWith('.cube'), isTrue);
        expect(lutPreviewMatrices[entry.key], hasLength(20));
      }
    });
  });
}
