import 'package:flutter_test/flutter_test.dart';
import 'package:gifcut/timeline_history.dart';
import 'package:gifcut/transition_timeline.dart';

void main() {
  group('TransitionTimeline', () {
    const clips = [
      TimelineClipRange(0, 4, timelineStart: 0),
      TimelineClipRange(8, 12, timelineStart: 4),
    ];

    test('applying a transition creates an exact clip overlap', () {
      final applied = TransitionTimeline.apply(
        clips: clips,
        leftIndex: 0,
        duration: 0.8,
      );

      expect(applied[0].timelineEnd, 4);
      expect(applied[1].timelineStart, closeTo(3.2, 0.0001));
      expect(applied[1].timelineEnd, closeTo(7.2, 0.0001));
      expect(
        TransitionTimeline.isApplied(
          outgoing: applied[0],
          incoming: applied[1],
          at: 4,
          duration: 0.8,
        ),
        isTrue,
      );
    });

    test('removing a transition restores the hard cut without changing source ranges', () {
      final applied = TransitionTimeline.apply(
        clips: clips,
        leftIndex: 0,
        duration: 0.8,
      );
      final removed = TransitionTimeline.remove(clips: applied, leftIndex: 0);

      expect(removed, clips);
    });

    test('duration is limited by both neighboring clip handles', () {
      final shortClips = [
        const TimelineClipRange(0, 1, timelineStart: 0),
        const TimelineClipRange(5, 9, timelineStart: 1),
      ];

      final applied = TransitionTimeline.apply(
        clips: shortClips,
        leftIndex: 0,
        duration: 3,
      );

      expect(applied[1].timelineStart, closeTo(0.5, 0.0001));
    });

    test('transition cannot be added across a timeline gap', () {
      expect(
        () => TransitionTimeline.apply(
          clips: const [
            TimelineClipRange(0, 4, timelineStart: 0),
            TimelineClipRange(8, 12, timelineStart: 5),
          ],
          leftIndex: 0,
          duration: 0.5,
        ),
        throwsArgumentError,
      );
    });

    test('xfade output offset and duration match the overlapped timeline', () {
      final offset = TransitionTimeline.xfadeOffset(
        composedDuration: 4,
        transitionDuration: 0.8,
      );
      final outputDuration =
          TransitionTimeline.composedDurationAfterTransition(
        composedDuration: 4,
        incomingDuration: 4,
        transitionDuration: 0.8,
      );

      expect(offset, closeTo(3.2, 0.0001));
      expect(outputDuration, closeTo(7.2, 0.0001));
    });

    test('adjacent overlapping clips expose their transition boundary', () {
      final applied = TransitionTimeline.apply(
        clips: clips,
        leftIndex: 0,
        duration: 0.5,
      );

      final boundaries = TransitionTimeline.boundaries(applied);
      expect(boundaries, hasLength(1));
      expect(boundaries.single.at, 4);
      expect(boundaries.single.leftIndex, 0);
      expect(boundaries.single.rightIndex, 1);
      expect(TransitionTimeline.boundaryAt(applied, 4), isNotNull);
      expect(TransitionTimeline.boundaryAt(applied, 3), isNull);
    });
  });
}
