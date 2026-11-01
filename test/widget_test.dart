import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gifcut/main.dart';

void main() {
  testWidgets('GifCut editor opens with import and timeline controls', (tester) async {
    await tester.pumpWidget(const GifCutApp());
    await tester.pump();

    expect(find.text('GifCut'), findsOneWidget);
    expect(find.byKey(const ValueKey('import-media-button')), findsOneWidget);
    expect(find.text('ТАЙМЛАЙН'), findsOneWidget);
    expect(find.text('Нажмите «Импорт видео», чтобы начать'), findsOneWidget);
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

    for (final key in const ['timeline-undo', 'timeline-redo']) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
      expect(tester.widget<IconButton>(find.byKey(ValueKey(key))).onPressed, isNull);
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
    expect(find.byTooltip('Сохранить проект'), findsOneWidget);
    final saveButton = find.ancestor(
      of: find.byIcon(Icons.save_outlined),
      matching: find.byType(IconButton),
    );
    expect(saveButton, findsOneWidget);
    expect(tester.widget<IconButton>(saveButton).onPressed, isNull);
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

    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    await tester.pump();
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

    expect(find.byType(SwitchListTile), findsNWidgets(3));
    expect(
      tester.takeException(),
      isNull,
      reason: 'Inspector switch controls must render inside Material surfaces.',
    );
  });

  testWidgets('CapCut-style media categories and effect cards open the right inspector', (tester) async {
    await tester.pumpWidget(const GifCutApp());
    await tester.pump();

    for (final category in const ['media', 'audio', 'text', 'stickers', 'effects', 'transitions', 'captions', 'filters']) {
      expect(find.byKey(ValueKey('library-category-$category')), findsOneWidget);
    }

    final effectsCategory = find.byKey(const ValueKey('library-category-effects'));
    await tester.ensureVisible(effectsCategory);
    await tester.tap(effectsCategory);
    await tester.pump();
    expect(find.text('ЭФФЕКТЫ ДЛЯ ВИДЕО'), findsOneWidget);
    final effectCard = find.byKey(const ValueKey('preset-card-effect:Чёрно-белый'));
    expect(effectCard, findsOneWidget);
    await tester.ensureVisible(effectCard);
    await tester.tap(effectCard);
    await tester.pump();
    expect(find.text('НАСТРОЙКИ ЭФФЕКТА'), findsOneWidget);
    expect(find.byKey(const ValueKey('apply-library-preset')), findsOneWidget);
    expect(tester.takeException(), isNull);

    final transitionsCategory = find.byKey(const ValueKey('library-category-transitions'));
    await tester.ensureVisible(transitionsCategory);
    await tester.tap(transitionsCategory);
    await tester.pump();
    expect(find.text('ПЕРЕХОДЫ МЕЖДУ КЛИПАМИ'), findsOneWidget);
    final transitionCard = find.byKey(const ValueKey('preset-card-transition:Растворение'));
    expect(transitionCard, findsOneWidget);
    await tester.ensureVisible(transitionCard);
    await tester.tap(transitionCard);
    await tester.pump();
    expect(find.text('НАСТРОЙКИ ПЕРЕХОДА'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview uses a black background by default and blur is an explicit toggle', (tester) async {
    await tester.pumpWidget(const GifCutApp());
    await tester.pump();

    final backgroundToggle = find.byKey(const ValueKey('canvas-background-blur-settings-toggle'));
    expect(backgroundToggle, findsOneWidget);
    expect(find.byKey(const ValueKey('canvas-blurred-background')), findsNothing);
    expect(backgroundToggle, findsOneWidget);

    await tester.tap(backgroundToggle);
    await tester.pump();

    expect(find.byKey(const ValueKey('canvas-background-blur-toggle')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('application title exposes the 0.3.81 version', (tester) async {
    await tester.pumpWidget(const GifCutApp());
    await tester.pump();

    expect(find.text('v0.3.81'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace keeps the preview left of the right-hand inspector', (tester) async {
    await tester.pumpWidget(const GifCutApp());
    await tester.pump();

    final preview = find.byKey(const ValueKey('preview-panel'));
    final inspector = find.byKey(const ValueKey('right-inspector-panel'));
    expect(preview, findsOneWidget);
    expect(inspector, findsOneWidget);
    expect(tester.getTopLeft(preview).dx, lessThan(tester.getTopLeft(inspector).dx));
    expect(tester.takeException(), isNull);
  });

}
