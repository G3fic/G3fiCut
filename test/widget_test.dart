import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    // The editor now exposes undo/redo in the left tool rail and timeline.
    // Check their visible tooltips and ensure the commands are disabled initially.
    for (final tooltip in const ['Отменить', 'Повторить']) {
      final button = find.descendant(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      );
      expect(find.byTooltip(tooltip), findsOneWidget);
      expect(tester.widget<IconButton>(button).onPressed, isNull);
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
    expect(find.byTooltip('Сохранить'), findsOneWidget);
    expect(find.byTooltip('Сохранить как'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.descendant(of: find.byTooltip('Сохранить'), matching: find.byType(IconButton))).onPressed,
      isNull,
    );
    expect(
      tester.widget<IconButton>(find.descendant(of: find.byTooltip('Сохранить как'), matching: find.byType(IconButton))).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop shortcut help is discoverable and opens', (tester) async {
    await tester.pumpWidget(const G3fiCutApp());
    await tester.pump();

    expect(find.byKey(const ValueKey('keyboard-shortcuts')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();

    expect(find.text('Горячие клавиши'), findsOneWidget);
    expect(find.text('На один кадр назад / вперёд'), findsOneWidget);
    expect(find.text('Ctrl + M'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('timeline snapping toggle is visible and interactive', (tester) async {
    await tester.pumpWidget(const G3fiCutApp());
    await tester.pump();

    final snapButton = find.byKey(const ValueKey('timeline-snap'));
    expect(snapButton, findsOneWidget);
    await tester.tap(snapButton);
    await tester.pump();
    expect(find.byTooltip('Привязка выключена'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace panes can be resized with their splitters', (tester) async {
    await tester.pumpWidget(const G3fiCutApp());
    await tester.pump();

    final mediaSplitter = find.byKey(const ValueKey('media-panel-splitter'));
    final inspectorSplitter = find.byKey(const ValueKey('inspector-panel-splitter'));
    final timelineSplitter = find.byKey(const ValueKey('timeline-panel-splitter'));
    expect(mediaSplitter, findsOneWidget);
    expect(inspectorSplitter, findsOneWidget);
    expect(timelineSplitter, findsOneWidget);

    await tester.drag(mediaSplitter, const Offset(28, 0));
    await tester.pump();
    await tester.drag(inspectorSplitter, const Offset(-24, 0));
    await tester.pump();
    await tester.drag(timelineSplitter, const Offset(0, -24));
    await tester.pump();

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
