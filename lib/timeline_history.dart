/// Immutable source-time range for one video clip on the timeline.
class TimelineClipRange {
  const TimelineClipRange(this.start, this.end, {double? timelineStart})
      : timelineStart = timelineStart ?? start;

  final double start;
  final double end;
  final double timelineStart;

  double get length => end - start;
  double get timelineEnd => timelineStart + length;

  @override
  bool operator ==(Object other) =>
      other is TimelineClipRange &&
      other.start == start &&
      other.end == end &&
      other.timelineStart == timelineStart;

  @override
  int get hashCode => Object.hash(start, end, timelineStart);
}


/// Immutable timing for one standalone effect block.
class TimelineEffectRange {
  const TimelineEffectRange(this.type, this.start, this.end);
  final String type;
  final double start;
  final double end;

  @override
  bool operator ==(Object other) =>
      other is TimelineEffectRange &&
      other.type == type && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(type, start, end);
}

/// Immutable transition attached to one cut between adjacent video clips.
class TimelineTransitionRange {
  const TimelineTransitionRange(this.type, this.at, this.duration);
  final String type;
  final double at;
  final double duration;

  @override
  bool operator ==(Object other) =>
      other is TimelineTransitionRange &&
      other.type == type && other.at == at && other.duration == duration;

  @override
  int get hashCode => Object.hash(type, at, duration);
}

/// An immutable snapshot of user-editable timeline state.
class TimelineSnapshot {
  TimelineSnapshot({
    required List<TimelineClipRange> videoClips,
    required this.selectedClipIndex,
    required this.audioPath,
    required this.audioClipStart,
    required this.audioClipEnd,
    List<TimelineEffectRange> effectClips = const [],
    List<TimelineTransitionRange> transitions = const [],
  })  : videoClips = List<TimelineClipRange>.unmodifiable(videoClips),
        effectClips = List<TimelineEffectRange>.unmodifiable(effectClips),
        transitions = List<TimelineTransitionRange>.unmodifiable(transitions);

  final List<TimelineClipRange> videoClips;
  final int selectedClipIndex;
  final String? audioPath;
  final double audioClipStart;
  final double audioClipEnd;
  final List<TimelineEffectRange> effectClips;
  final List<TimelineTransitionRange> transitions;

  bool sameContentAs(TimelineSnapshot other) {
    if (selectedClipIndex != other.selectedClipIndex ||
        audioPath != other.audioPath ||
        audioClipStart != other.audioClipStart ||
        audioClipEnd != other.audioClipEnd ||
        videoClips.length != other.videoClips.length ||
        effectClips.length != other.effectClips.length ||
        transitions.length != other.transitions.length) {
      return false;
    }

    for (var i = 0; i < videoClips.length; i++) {
      final left = videoClips[i];
      final right = other.videoClips[i];
      if (left.start != right.start ||
          left.end != right.end ||
          left.timelineStart != right.timelineStart) {
        return false;
      }
    }
    for (var i = 0; i < effectClips.length; i++) {
      if (effectClips[i] != other.effectClips[i]) return false;
    }
    for (var i = 0; i < transitions.length; i++) {
      if (transitions[i] != other.transitions[i]) return false;
    }
    return true;
  }
}

/// Bounded undo/redo history for timeline snapshots.
///
/// The undo stack stores pre-edit states. Recording a new edit after an undo
/// invalidates the redo stack, as expected in desktop editing applications.
class TimelineHistory {
  TimelineHistory({this.maxEntries = 100}) : assert(maxEntries > 0);

  final int maxEntries;
  final List<TimelineSnapshot> _undoStates = [];
  final List<TimelineSnapshot> _redoStates = [];

  bool get canUndo => _undoStates.isNotEmpty;
  bool get canRedo => _redoStates.isNotEmpty;

  void record({
    required TimelineSnapshot before,
    required TimelineSnapshot after,
  }) {
    if (before.sameContentAs(after)) return;
    _pushBounded(_undoStates, before);
    _redoStates.clear();
  }

  TimelineSnapshot? undo(TimelineSnapshot current) {
    if (_undoStates.isEmpty) return null;
    _pushBounded(_redoStates, current);
    return _undoStates.removeLast();
  }

  TimelineSnapshot? redo(TimelineSnapshot current) {
    if (_redoStates.isEmpty) return null;
    _pushBounded(_undoStates, current);
    return _redoStates.removeLast();
  }

  void clear() {
    _undoStates.clear();
    _redoStates.clear();
  }

  void _pushBounded(List<TimelineSnapshot> states, TimelineSnapshot state) {
    states.add(state);
    if (states.length > maxEntries) states.removeAt(0);
  }
}
