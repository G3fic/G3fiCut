import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g3ficut/main.dart';

void main() {
  testWidgets('GifCut editor opens with import and timeline controls', (tester) async {
    await tester.pumpWidget(const G3fiCutApp());
    await tester.pump();

    expect(find.text('gifcut'), findsOneWidget);
    expect(find.byTooltip('Импортировать видео'), findsOneWidget);
    expect(find.text('ТАЙМЛАЙН'), findsOneWidget);
    expect(find.text('Ваше видео появится здесь'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'The editor must open without layout or initialization exceptions.');
  });

  test('version comparison detects newer semantic versions', () {
    expect(isVersionNewer('v0.3.0', '0.2.0'), isTrue);
    expect(isVersionNewer('0.2.1', '0.2.0'), isTrue);
    expect(isVersionNewer('0.2.0', '0.2.0'), isFalse);
    expect(isVersionNewer('0.1.9', '0.2.0'), isFalse);
    expect(isVersionNewer('1.0.0', '0.99.99'), isTrue);
  });
  testWidgets('undo and redo controls are visible and disabled without edits', (tester) async {
    await tester.pumpWidget(const G3fiCutApp());
    await tester.pump();

    // Use explicit keys: the controls live in separate scrollable panels,
    // and disabled tooltip widgets are not guaranteed to enter the finder tree.
    for (final key in const ['toolbar-undo', 'toolbar-redo']) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byKey(ValueKey(key))).onPressed,
        isNull,
      );
    }
    for (final key in const ['timeline-undo', 'timeline-redo']) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
      expect(
        tester.widget<IconButton>(find.byKey(ValueKey(key))).onPressed,
        isNull,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('project controls are visible and save is disabled without media', (tester) async {
    await tester.pumpWidget(const G3fiCutApp());
    await tester.pump();

    expect(find.byTooltip('Открыть проект'), findsOneWidget);
    expect(find.byTooltip('Сохранить проект'), findsOneWidget);
    expect(find.byTooltip('Сохранить как'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.ancestor(of: find.byTooltip('Сохранить проект'), matching: find.byType(IconButton))).onPressed,
      isNull,
    );
    expect(
      tester.widget<IconButton>(find.ancestor(of: find.byTooltip('Сохранить как'), matching: find.byType(IconButton))).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('inspector switches render without Material or ink errors', (tester) async {
    await tester.pumpWidget(const G3fiCutApp());
    await tester.pump();

    expect(find.byType(SwitchListTile), findsNWidgets(2));
    expect(
      tester.takeException(),
      isNull,
      reason: 'Inspector switch controls must render inside Material surfaces.',
    );
  });

}
