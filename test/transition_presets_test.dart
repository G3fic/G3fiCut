import 'package:flutter_test/flutter_test.dart';
import 'package:gifcut/project_document.dart';
import 'package:gifcut/transition_presets.dart';

void main() {
  test('every project transition has a valid FFmpeg xfade preset', () {
    expect(
      transitionFilterNames.keys.toSet(),
      ProjectTransition.supportedTypes,
    );
    expect(transitionFilterNames.values.toSet().length,
        transitionFilterNames.length);
    expect(
      transitionFilterNames.values,
      everyElement(isNotEmpty),
    );
  });

  test('unknown transition names fall back to a supported fade', () {
    expect(transitionFilterName('not a transition'), 'fade');
  });
}
