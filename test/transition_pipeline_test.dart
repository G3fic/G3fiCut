import 'package:flutter_test/flutter_test.dart';
import 'package:gifcut/effect_catalog.dart';
import 'package:gifcut/transition_pipeline.dart';

void main() {
  group('Transition pipeline binding', () {
    test('attaches a marker only to the exact adjacent video cut', () {
      final plan = buildTransitionPipeline(
        segments: const [
          TransitionPipelineSegment(start: 0, end: 4),
          TransitionPipelineSegment(start: 4, end: 8),
        ],
        transitions: const [
          TransitionPipelineMarker(type: 'wipeleft', at: 4, duration: 0.6),
        ],
        frameRate: 30,
      );

      expect(plan, hasLength(1));
      expect(plan.single.type, 'wipeleft');
      expect(plan.single.hasTransition, isTrue);
      expect(plan.single.duration, closeTo(0.6, 1e-9));
      expect(plan.single.offset, closeTo(3.4, 1e-9));
      expect(plan.single.outputDuration, closeTo(7.4, 1e-9));
    });

    test('ignores stale markers that no longer match a clip cut', () {
      final plan = buildTransitionPipeline(
        segments: const [
          TransitionPipelineSegment(start: 0, end: 4),
          TransitionPipelineSegment(start: 4, end: 8),
        ],
        transitions: const [
          TransitionPipelineMarker(type: 'circleopen', at: 3.8, duration: 0.6),
        ],
        frameRate: 30,
      );

      expect(plan.single.hasTransition, isFalse);
      expect(plan.single.outputDuration, closeTo(8, 1e-9));
    });

    test('never applies transitions across a gap segment', () {
      final plan = buildTransitionPipeline(
        segments: const [
          TransitionPipelineSegment(start: 0, end: 4),
          TransitionPipelineSegment(start: 4, end: 4.5, isGap: true),
          TransitionPipelineSegment(start: 4.5, end: 8.5),
        ],
        transitions: const [
          TransitionPipelineMarker(type: 'fade', at: 4, duration: 0.5),
          TransitionPipelineMarker(type: 'fade', at: 4.5, duration: 0.5),
        ],
        frameRate: 30,
      );

      expect(plan, hasLength(2));
      expect(plan.every((step) => !step.hasTransition), isTrue);
      expect(plan.last.outputDuration, closeTo(8.5, 1e-9));
    });

    test('frame-aligns and clamps transition duration to available clip handles', () {
      final plan = buildTransitionPipeline(
        segments: const [
          TransitionPipelineSegment(start: 0, end: 0.6),
          TransitionPipelineSegment(start: 0.6, end: 1.0),
        ],
        transitions: const [
          TransitionPipelineMarker(type: 'dissolve', at: 0.6, duration: 0.8),
        ],
        frameRate: 30,
      );

      // The incoming clip is only 0.4 seconds long; xfade may consume at most
      // half of it, and must use whole frames at the output frame rate.
      expect(plan.single.duration, closeTo(0.2, 1e-9));
      expect(plan.single.duration * 30, closeTo(6, 1e-9));
      expect(plan.single.offset, closeTo(0.4, 1e-9));
      expect(plan.single.outputDuration, closeTo(0.8, 1e-9));
    });

    test('frame-aligns source segment durations before cumulative offsets', () {
      final plan = buildTransitionPipeline(
        segments: const [
          TransitionPipelineSegment(start: 0, end: 1.01),
          TransitionPipelineSegment(start: 1.01, end: 2.03),
        ],
        transitions: const [
          TransitionPipelineMarker(type: 'fade', at: 1.01, duration: 0.3),
        ],
        frameRate: 30,
      );

      expect(plan.single.duration, closeTo(0.3, 1e-9));
      expect(plan.single.offset, closeTo(0.7, 1e-9));
      expect(plan.single.outputDuration, closeTo(1.7333333333, 1e-8));
    });

    test('calculates offsets cumulatively for multiple consecutive transitions', () {
      final plan = buildTransitionPipeline(
        segments: const [
          TransitionPipelineSegment(start: 0, end: 4),
          TransitionPipelineSegment(start: 4, end: 8),
          TransitionPipelineSegment(start: 8, end: 12),
        ],
        transitions: const [
          TransitionPipelineMarker(type: 'fade', at: 4, duration: 0.6),
          TransitionPipelineMarker(type: 'slideleft', at: 8, duration: 0.3),
        ],
        frameRate: 30,
      );

      expect(plan, hasLength(2));
      expect(plan[0].offset, closeTo(3.4, 1e-9));
      expect(plan[0].outputDuration, closeTo(7.4, 1e-9));
      expect(plan[1].offset, closeTo(7.1, 1e-9));
      expect(plan[1].outputDuration, closeTo(11.1, 1e-9));
    });

    test('every built-in transition is eligible for the same real export path', () {
      final types = builtinTransitionFilters.keys.toList()..sort();
      expect(types, isNotEmpty);

      for (final type in types) {
        final plan = buildTransitionPipeline(
          segments: const [
            TransitionPipelineSegment(start: 0, end: 3),
            TransitionPipelineSegment(start: 3, end: 6),
          ],
          transitions: [
            TransitionPipelineMarker(type: type, at: 3, duration: 0.5),
          ],
          frameRate: 30,
        );

        expect(plan.single.type, type, reason: type);
        expect(plan.single.hasTransition, isTrue, reason: type);
        expect(transitionFilterName(type), isNotEmpty, reason: type);
      }
    });

    test('rejects overlapping or invalid segments before building a graph', () {
      expect(
        () => buildTransitionPipeline(
          segments: const [
            TransitionPipelineSegment(start: 0, end: 4),
            TransitionPipelineSegment(start: 3.5, end: 8),
          ],
          transitions: const [],
          frameRate: 30,
        ),
        throwsArgumentError,
      );
      expect(
        () => buildTransitionPipeline(
          segments: const [
            TransitionPipelineSegment(start: 0, end: 4),
            TransitionPipelineSegment(start: 4, end: 8),
          ],
          transitions: const [],
          frameRate: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
