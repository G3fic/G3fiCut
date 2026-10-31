import 'package:flutter_test/flutter_test.dart';
import 'package:gifcut/timeline_editing.dart';
import 'package:gifcut/timeline_history.dart';

void main() {
  group('TimelineEditing', () {
    final source = [
      const TimelineClipRange(0, 4, timelineStart: 0),
      const TimelineClipRange(8, 12, timelineStart: 4),
    ];

    test('split maps sequence time to source time', () {
      expect(TimelineEditing.splitAt(source, 1, 6), [
        const TimelineClipRange(0, 4, timelineStart: 0),
        const TimelineClipRange(8, 10, timelineStart: 4),
        const TimelineClipRange(10, 12, timelineStart: 6),
      ]);
    });

    test('duplicate inserts after selection and shifts following clips', () {
      expect(TimelineEditing.duplicateAfter(source, 0), [
        const TimelineClipRange(0, 4, timelineStart: 0),
        const TimelineClipRange(0, 4, timelineStart: 4),
        const TimelineClipRange(8, 12, timelineStart: 8),
      ]);
    });

    test('move inserts clip at sequence position and pushes later clips', () {
      final clips = [
        const TimelineClipRange(0, 4, timelineStart: 0),
        const TimelineClipRange(4, 8, timelineStart: 4),
        const TimelineClipRange(8, 12, timelineStart: 8),
      ];
      expect(TimelineEditing.moveInsert(clips, 2, 0), [
        const TimelineClipRange(8, 12, timelineStart: 0),
        const TimelineClipRange(0, 4, timelineStart: 4),
        const TimelineClipRange(4, 8, timelineStart: 8),
      ]);
    });

    test('move never changes the source in/out points or clip duration', () {
      final clips = [
        const TimelineClipRange(12, 18, timelineStart: 2),
        const TimelineClipRange(30, 34, timelineStart: 8),
      ];

      final moved = TimelineEditing.moveInsert(clips, 0, 7);

      expect(moved.first.start, 12);
      expect(moved.first.end, 18);
      expect(moved.first.length, 6);
      expect(moved.first.timelineStart, 7);
      expect(moved.last.start, 30);
      expect(moved.last.end, 34);
      expect(moved.last.length, 4);
    });

    test('ripple trim start shifts following clips left', () {
      final clips = [
        const TimelineClipRange(0, 6, timelineStart: 0),
        const TimelineClipRange(6, 10, timelineStart: 6),
      ];
      expect(TimelineEditing.trimStartRipple(clips, 0, 2), [
        const TimelineClipRange(2, 6, timelineStart: 0),
        const TimelineClipRange(6, 10, timelineStart: 4),
      ]);
    });

    test('ripple trim end shifts following clips left', () {
      final clips = [
        const TimelineClipRange(0, 6, timelineStart: 0),
        const TimelineClipRange(6, 10, timelineStart: 6),
      ];
      expect(TimelineEditing.trimEndRipple(clips, 0, 4), [
        const TimelineClipRange(0, 4, timelineStart: 0),
        const TimelineClipRange(6, 10, timelineStart: 4),
      ]);
    });

    test('ripple delete closes the removed clip duration', () {
      final clips = [
        const TimelineClipRange(0, 4, timelineStart: 0),
        const TimelineClipRange(4, 8, timelineStart: 4),
        const TimelineClipRange(8, 12, timelineStart: 8),
      ];
      expect(TimelineEditing.rippleDelete(clips, 1), [
        const TimelineClipRange(0, 4, timelineStart: 0),
        const TimelineClipRange(8, 12, timelineStart: 4),
      ]);
    });

    test('regular delete leaves a sequence gap', () {
      expect(TimelineEditing.deleteLeaveGap(source, 0).single.timelineStart, 4);
    });

    test('effect placement never overlaps existing effects', () {
      final effects = [
        const TimelineEffectRange('blur', 2, 4),
        const TimelineEffectRange('sepia', 6, 8),
      ];

      expect(
        TimelineEditing.findAvailableEffectStart(
          effects: effects,
          preferred: 3,
          length: 1.5,
          timelineEnd: 10,
        ),
        4,
      );
      expect(
        TimelineEditing.findAvailableEffectStart(
          effects: effects,
          preferred: 3,
          length: 3,
          timelineEnd: 10,
        ),
        isNull,
      );
      expect(
        TimelineEditing.findAvailableEffectStart(
          effects: effects,
          preferred: 7,
          length: 2,
          timelineEnd: 8,
        ),
        isNull,
      );
    });

    test('effect edge resize respects neighboring effect blocks', () {
      final effects = [
        const TimelineEffectRange('blur', 1, 3),
        const TimelineEffectRange('sepia', 4, 6),
        const TimelineEffectRange('warm', 7, 9),
      ];

      expect(
        TimelineEditing.resizeEffectEdge(
          effects: effects,
          index: 1,
          requestedTime: 2,
          timelineEnd: 10,
          resizeStart: true,
        ),
        const TimelineEffectRange('sepia', 3, 6),
      );
      expect(
        TimelineEditing.resizeEffectEdge(
          effects: effects,
          index: 1,
          requestedTime: 8,
          timelineEnd: 10,
          resizeStart: false,
        ),
        const TimelineEffectRange('sepia', 4, 7),
      );
    });

    test('rejects split at clip edges', () {
      expect(() => TimelineEditing.splitAt(source, 0, 0.01), throwsArgumentError);
      expect(() => TimelineEditing.splitAt(source, 0, 4), throwsArgumentError);
    });
  });
}
