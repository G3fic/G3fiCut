import 'package:flutter_test/flutter_test.dart';
import 'package:g3ficut/timeline_editing.dart';
import 'package:g3ficut/timeline_history.dart';

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

    test('rejects split at clip edges', () {
      expect(() => TimelineEditing.splitAt(source, 0, 0.01), throwsArgumentError);
      expect(() => TimelineEditing.splitAt(source, 0, 4), throwsArgumentError);
    });
  });
}
