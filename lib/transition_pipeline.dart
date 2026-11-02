/// Resolves cut-bound transitions into frame-aligned FFmpeg xfade steps.
///
/// A transition belongs to the join between two adjacent, non-gap timeline
/// segments. The transition interval consumes the tail of the outgoing segment
/// and the head of the incoming segment, so every xfade shortens the resulting
/// sequence by exactly its frame-aligned duration.
class TransitionPipelineSegment {
  const TransitionPipelineSegment({
    required this.start,
    required this.end,
    this.isGap = false,
  });

  final double start;
  final double end;
  final bool isGap;

  double get duration => end - start;
}

class TransitionPipelineMarker {
  const TransitionPipelineMarker({
    required this.type,
    required this.at,
    required this.duration,
  });

  final String type;
  final double at;
  final double duration;
}

class TransitionPipelineStep {
  const TransitionPipelineStep({
    required this.segmentIndex,
    required this.type,
    required this.duration,
    required this.offset,
    required this.outputDuration,
  });

  /// Index of the incoming segment in the ordered segment list.
  final int segmentIndex;

  /// Null means that this join is a straight concatenation.
  final String? type;

  /// Actual xfade duration, rounded to whole output frames.
  final double duration;

  /// Position of the transition in the already-composited output stream.
  final double offset;

  /// Total output duration after this segment has been joined.
  final double outputDuration;

  bool get hasTransition => type != null && duration > 0;
}

const double transitionCutTolerance = 0.025;

/// Builds one deterministic join step for every segment after the first.
///
/// Markers that do not point to an actual adjacent clip cut (or point across a
/// gap) are deliberately ignored. This prevents stale transition markers from
/// accidentally applying to an unrelated clip after timeline edits.
List<TransitionPipelineStep> buildTransitionPipeline({
  required List<TransitionPipelineSegment> segments,
  required List<TransitionPipelineMarker> transitions,
  required double frameRate,
}) {
  if (segments.length < 2) return const [];
  if (!frameRate.isFinite || frameRate <= 0) {
    throw ArgumentError.value(frameRate, 'frameRate', 'Must be finite and positive.');
  }

  for (var i = 0; i < segments.length; i++) {
    final segment = segments[i];
    if (!segment.start.isFinite ||
        !segment.end.isFinite ||
        segment.end <= segment.start) {
      throw ArgumentError('Invalid transition segment at index $i.');
    }
    if (i > 0 && segment.start < segments[i - 1].end - transitionCutTolerance) {
      throw ArgumentError('Transition segments must be ordered and cannot overlap.');
    }
  }

  // Segment exporters cap output with -frames:v, using the same rounded count.
  double frameAligned(double seconds) => (seconds * frameRate).round() / frameRate;

  final segmentDurations = segments
      .map((segment) => frameAligned(segment.duration))
      .toList(growable: false);
  var accumulatedDuration = segmentDurations.first;
  final steps = <TransitionPipelineStep>[];

  for (var i = 1; i < segments.length; i++) {
    final previous = segments[i - 1];
    final current = segments[i];
    TransitionPipelineMarker? marker;

    final isContiguousCut = !previous.isGap &&
        !current.isGap &&
        (previous.end - current.start).abs() <= transitionCutTolerance;

    if (isContiguousCut) {
      for (final candidate in transitions) {
        if (!candidate.at.isFinite ||
            !candidate.duration.isFinite ||
            candidate.duration <= 0 ||
            (candidate.at - current.start).abs() > transitionCutTolerance) {
          continue;
        }
        if (marker == null ||
            (candidate.at - current.start).abs() <
                (marker.at - current.start).abs()) {
          marker = candidate;
        }
      }
    }

    var transitionDuration = 0.0;
    String? transitionType;
    if (marker != null) {
      final previousDuration = segmentDurations[i - 1];
      final currentDuration = segmentDurations[i];
      final maximum = previousDuration < currentDuration
          ? previousDuration / 2
          : currentDuration / 2;
      final requested = marker.duration < maximum ? marker.duration : maximum;
      final maximumFrames = (maximum * frameRate + 1e-9).floor();
      if (maximumFrames >= 1 && requested > 0) {
        final requestedFrames = (requested * frameRate).round();
        final frames = requestedFrames.clamp(1, maximumFrames);
        transitionDuration = frames / frameRate;
        transitionType = marker.type;
      }
    }

    final offset = transitionDuration > 0
        ? accumulatedDuration - transitionDuration
        : accumulatedDuration;
    if (transitionDuration > 0 && offset < -transitionCutTolerance) {
      transitionDuration = 0;
      transitionType = null;
    }

    accumulatedDuration += segmentDurations[i] - transitionDuration;
    steps.add(TransitionPipelineStep(
      segmentIndex: i,
      type: transitionType,
      duration: transitionDuration,
      offset: transitionType == null ? 0 : (offset < 0 ? 0 : offset),
      outputDuration: accumulatedDuration,
    ));
  }

  return List<TransitionPipelineStep>.unmodifiable(steps);
}
