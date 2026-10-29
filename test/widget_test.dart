import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g3ficut/main.dart';

void main() {
  testWidgets('GifCut editor opens with import and timeline controls', (tester) async {
    await tester.pumpWidget(const G3fiCutApp());
    await tester.pump();

    expect(find.text('GifCut'), findsOneWidget);
    expect(find.text('Импорт видео'), findsOneWidget);
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

    expect(find.byTooltip('Отменить (Ctrl+Z)'), findsOneWidget);
    expect(find.byTooltip('Повторить (Ctrl+Y, Ctrl+Shift+Z)'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Отменить')).onPressed,
      isNull,
    );
    expect(
      tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Повторить')).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('project controls are visible and save is disabled without media', (tester) async {
    await tester.pumpWidget(const G3fiCutApp());
    await tester.pump();

    expect(find.text('Открыть проект'), findsOneWidget);
    expect(find.text('Сохранить'), findsOneWidget);
    expect(find.text('Сохранить как…'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Сохранить')).onPressed,
      isNull,
    );
    expect(
      tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Сохранить как…')).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

}
