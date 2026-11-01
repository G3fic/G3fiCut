import 'timeline_history.dart';

/// Geometry and export timing for a transition that overlaps two adjacent
/// timeline clips. [TimelineTransitionRange.at] is the end of the outgoing
/// clip; the transition occupies [at - duration, at].
class TransitionBoundary {
  const TransitionBoundary({
    required this.leftIndex,
    required this.rightIndex,
    required this.at,
  });

  final int leftIndex;
  final int rightIndex;
  final double at;
}

class TransitionTimeline {
  static const double minimumDuration = 0.1;
  static const double epsilon = 0.025;
  static const double maximumDuration = 5.0;

  static double maxDuration(
    TimelineClipRange outgoing,
    TimelineClipRange incoming,
  ) =>
      _min3(
        maximumDuration,
        outgoing.length / 2,
        incoming.length / 2,
      );

  static List<TransitionBoundary> boundaries(List<TimelineClipRange> clips) {
    final ordered = List<TimelineClipRange>.of(clips)
      ..sort((a, b) => a.timelineStart.compareTo(b.timelineStart));
    final result = <TransitionBoundary>[];
    for (var rightIndex = 1; rightIndex < ordered.length; rightIndex++) {
      final left = ordered[rightIndex - 1];
      final right = ordered[rightIndex];
      final at = left.timelineEnd;
      // A hard cut touches; an applied transition overlaps by its duration.
      if (right.timelineStart <= at + epsilon &&
          at - right.timelineStart <= maxDuration(left, right) + epsilon) {
        result.add(TransitionBoundary(
          leftIndex: rightIndex - 1,
          rightIndex: rightIndex,
          at: at,
        ));
      }
    }
    return result;
  }

  static TransitionBoundary? boundaryAt(
    List<TimelineClipRange> clips,
    double at,
  ) {
    for (final boundary in boundaries(clips)) {
      if ((boundary.at - at).abs() <= epsilon) return boundary;
    }
    return null;
  }

  static List<TimelineClipRange> apply({
    required List<TimelineClipRange> clips,
    required int leftIndex,
    required double duration,
  }) {
    if (leftIndex < 0 || leftIndex + 1 >= clips.length) {
      throw RangeError.index(leftIndex, clips, 'leftIndex');
    }
    if (!duration.isFinite) {
      throw ArgumentError.value(duration, 'duration');
    }
    final outgoing = clips[leftIndex];
    final incoming = clips[leftIndex + 1];
    final at = outgoing.timelineEnd;
    if (incoming.timelineStart > at + epsilon) {
      throw ArgumentError('Переход нельзя поставить через пустой участок.');
    }
    final maximum = maxDuration(outgoing, incoming);
    if (maximum < minimumDuration) {
      throw ArgumentError('Клипы слишком короткие для перехода.');
    }
    final actualDuration = duration
        .clamp(minimumDuration, maximum)
        .toDouble();
    final result = List<TimelineClipRange>.of(clips);
    result[leftIndex + 1] = TimelineClipRange(
      incoming.start,
      incoming.end,
      timelineStart: at - actualDuration,
    );
    return result;
  }

  static List<TimelineClipRange> remove({
    required List<TimelineClipRange> clips,
    required int leftIndex,
  }) {
    if (leftIndex < 0 || leftIndex + 1 >= clips.length) {
      throw RangeError.index(leftIndex, clips, 'leftIndex');
    }
    final outgoing = clips[leftIndex];
    final incoming = clips[leftIndex + 1];
    return List<TimelineClipRange>.of(clips)
      ..[leftIndex + 1] = TimelineClipRange(
        incoming.start,
        incoming.end,
        timelineStart: outgoing.timelineEnd,
      );
  }

  static bool isApplied({
    required TimelineClipRange outgoing,
    required TimelineClipRange incoming,
    required double at,
    required double duration,
  }) =>
      (outgoing.timelineEnd - at).abs() <= epsilon &&
      (incoming.timelineStart - (at - duration)).abs() <= epsilon;

  /// FFmpeg xfade's offset is the start of the overlap measured in the
  /// already-composed output stream.
  static double xfadeOffset({
    required double composedDuration,
    required double transitionDuration,
  }) =>
      (composedDuration - transitionDuration)
          .clamp(0.0, double.infinity)
          .toDouble();

  static double composedDurationAfterTransition({
    required double composedDuration,
    required double incomingDuration,
    required double transitionDuration,
  }) =>
      composedDuration + incomingDuration - transitionDuration;

  static double _min3(double a, double b, double c) =>
      a < b ? (a < c ? a : c) : (b < c ? b : c);
}
