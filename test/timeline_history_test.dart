import 'package:flutter_test/flutter_test.dart';
import 'package:g3ficut/timeline_history.dart';

TimelineSnapshot snapshot({
  List<TimelineClipRange> clips = const [],
  int selected = 0,
  String? audioPath,
  double audioStart = 0,
  double audioEnd = 0,
}) =>
    TimelineSnapshot(
      videoClips: clips,
      selectedClipIndex: selected,
      audioPath: audioPath,
      audioClipStart: audioStart,
      audioClipEnd: audioEnd,
    );

void main() {
  group('TimelineHistory', () {
    test('undo and redo restore complete video timeline state', () {
      final history = TimelineHistory();
      final before = snapshot(clips: [const TimelineClipRange(0, 12)]);
      final after = snapshot(
        clips: [const TimelineClipRange(0, 4), const TimelineClipRange(4, 12)],
        selected: 1,
      );

      history.record(before: before, after: after);

      expect(history.canUndo, isTrue);
      expect(history.canRedo, isFalse);
      final undone = history.undo(after);
      expect(undone?.sameContentAs(before), isTrue);
      expect(history.canRedo, isTrue);
      final redone = history.redo(undone!);
      expect(redone?.sameContentAs(after), isTrue);
      expect(history.canUndo, isTrue);
    });

    test('records sequence placement changes with identical source ranges', () {
      final history = TimelineHistory();
      final before = snapshot(clips: [const TimelineClipRange(0, 4, timelineStart: 0)]);
      final after = snapshot(clips: [const TimelineClipRange(0, 4, timelineStart: 4)]);
      history.record(before: before, after: after);
      expect(history.canUndo, isTrue);
      expect(history.undo(after)?.videoClips.single.timelineStart, 0);
    });

    test('does not record a no-op edit', () {
      final history = TimelineHistory();
      final state = snapshot(clips: [const TimelineClipRange(0, 5)]);

      history.record(before: state, after: snapshot(clips: [const TimelineClipRange(0, 5)]));

      expect(history.canUndo, isFalse);
      expect(history.canRedo, isFalse);
    });

    test('clears redo states when a new edit follows undo', () {
      final history = TimelineHistory();
      final first = snapshot(selected: 0);
      final second = snapshot(selected: 1);
      final alternate = snapshot(selected: 2);

      history.record(before: first, after: second);
      expect(history.undo(second)?.sameContentAs(first), isTrue);
      history.record(before: first, after: alternate);

      expect(history.canRedo, isFalse);
      expect(history.redo(first), isNull);
    });

    test('restores detached audio path and trim boundaries', () {
      final history = TimelineHistory();
      final before = snapshot(audioPath: r'C:\media\music.wav', audioStart: 0, audioEnd: 30);
      final after = snapshot(audioPath: r'C:\media\music.wav', audioStart: 5.25, audioEnd: 18.5);

      history.record(before: before, after: after);
      final undone = history.undo(after);
      expect(undone?.audioPath, r'C:\media\music.wav');
      expect(undone?.audioClipStart, 0);
      expect(undone?.audioClipEnd, 30);

      final redone = history.redo(undone!);
      expect(redone?.audioClipStart, 5.25);
      expect(redone?.audioClipEnd, 18.5);
    });

    test('clear removes both undo and redo history', () {
      final history = TimelineHistory();
      final first = snapshot(selected: 0);
      final second = snapshot(selected: 1);

      history.record(before: first, after: second);
      expect(history.undo(second)?.sameContentAs(first), isTrue);
      expect(history.canRedo, isTrue);

      history.clear();

      expect(history.canUndo, isFalse);
      expect(history.canRedo, isFalse);
      expect(history.undo(first), isNull);
      expect(history.redo(first), isNull);
    });

    test('keeps only the newest states when max history depth is reached', () {
      final history = TimelineHistory(maxEntries: 2);
      var state = snapshot(selected: 0);

      for (var i = 1; i <= 3; i++) {
        final next = snapshot(selected: i);
        history.record(before: state, after: next);
        state = next;
      }

      expect(history.undo(state)?.selectedClipIndex, 2);
      expect(history.undo(snapshot(selected: 2))?.selectedClipIndex, 1);
      expect(history.undo(snapshot(selected: 1)), isNull);
    });
  });
}
