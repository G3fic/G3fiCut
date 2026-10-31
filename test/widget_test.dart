import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gifcut/main.dart';

void main() {
  testWidgets('GifCut editor opens with import and timeline controls', (tester) async {
    await tester.pumpWidget(const GifCutApp());
    await tester.pump();

    expect(find.text('GifCut'), findsOneWidget);
    expect(find.byTooltip('Импортировать видео'), findsOneWidget);
    expect(find.byKey(const ValueKey('media-import-photo')), findsOneWidget);
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
    await tester.pumpWidget(const GifCutApp());
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
    await tester.pumpWidget(const GifCutApp());
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
    await tester.pumpWidget(const GifCutApp());
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
    await tester.pumpWidget(const GifCutApp());
    await tester.pump();

    final snapButton = find.byKey(const ValueKey('timeline-snap'));
    expect(snapButton, findsOneWidget);
    await tester.tap(snapButton);
    await tester.pump();
    expect(find.byTooltip('Привязка выключена'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('video canvas pointer drag continues across multiple moving frames', (tester) async {
    var offset = Offset.zero;
    final deltas = <Offset>[];

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Center(
            child: Transform.translate(
              offset: offset,
              child: ContinuousPointerDrag(
                key: const ValueKey('continuous-pointer-drag-test'),
                onDelta: (delta) {
                  deltas.add(delta);
                  setState(() => offset += delta);
                },
                child: const SizedBox(
                  width: 100,
                  height: 100,
                  child: ColoredBox(color: Colors.blue),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(tester.getCenter(
      find.byKey(const ValueKey('continuous-pointer-drag-test')),
    ));
    await gesture.moveBy(const Offset(8, 6));
    await tester.pump();
    await gesture.moveBy(const Offset(10, 7));
    await tester.pump();
    await gesture.moveBy(const Offset(12, 8));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(deltas, const [Offset(8, 6), Offset(10, 7), Offset(12, 8)]);
    expect(offset, const Offset(30, 21));
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace panes can be resized with their splitters', (tester) async {
    await tester.pumpWidget(const GifCutApp());
    await tester.pump();

    final mediaSplitter = find.byKey(const ValueKey('media-panel-splitter'));
    final inspectorSplitter = find.byKey(const ValueKey('inspector-panel-splitter'));
    final timelineSplitter = find.byKey(const ValueKey('timeline-panel-splitter'));
    expect(mediaSplitter, findsOneWidget);
    expect(inspectorSplitter, findsOneWidget);
    expect(timelineSplitter, findsOneWidget);

    await tester.drag(mediaSplitter, const Offset(-28, 0));
    await tester.pump();
    await tester.drag(inspectorSplitter, const Offset(24, 0));
    await tester.pump();
    await tester.drag(timelineSplitter, const Offset(0, -24));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('inspector switches render without Material or ink errors', (tester) async {
    await tester.pumpWidget(const GifCutApp());
    await tester.pump();

    expect(find.byType(SwitchListTile), findsNWidgets(2));
    expect(
      tester.takeException(),
      isNull,
      reason: 'Inspector switch controls must render inside Material surfaces.',
    );
  });

  testWidgets('media and effects libraries are available in adjacent tabs', (tester) async {
    await tester.pumpWidget(const GifCutApp());
    await tester.pump();

    expect(find.byKey(const ValueKey('media-library-media')), findsOneWidget);
    final effectsTab = find.byKey(const ValueKey('media-library-effects'));
    expect(effectsTab, findsOneWidget);
    await tester.tap(effectsTab);
    await tester.pump();

    expect(find.text('СТАНДАРТНЫЕ ЭФФЕКТЫ'), findsOneWidget);
    expect(find.text('СТАНДАРТНЫЕ ПЕРЕХОДЫ'), findsOneWidget);
    expect(find.text('Чёрно-белый'), findsOneWidget);
    expect(find.text('Растворение'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('hover-preview-effect:Чёрно-белый')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('hover-preview-transition:Растворение')),
      findsOneWidget,
    );
    expect(find.byTooltip('Проверить обновления'), findsNothing);
    expect(tester.takeException(), isNull);
  });

}
