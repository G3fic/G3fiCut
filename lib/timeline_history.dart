/// Immutable source-time range for one video clip on the timeline.
class TimelineClipRange {
  const TimelineClipRange(this.start, this.end);

  final double start;
  final double end;

  double get length => end - start;
}

/// An immutable snapshot of user-editable timeline state.
class TimelineSnapshot {
  TimelineSnapshot({
    required List<TimelineClipRange> videoClips,
    required this.selectedClipIndex,
    required this.audioPath,
    required this.audioClipStart,
    required this.audioClipEnd,
  }) : videoClips = List<TimelineClipRange>.unmodifiable(videoClips);

  final List<TimelineClipRange> videoClips;
  final int selectedClipIndex;
  final String? audioPath;
  final double audioClipStart;
  final double audioClipEnd;

  bool sameContentAs(TimelineSnapshot other) {
    if (selectedClipIndex != other.selectedClipIndex ||
        audioPath != other.audioPath ||
        audioClipStart != other.audioClipStart ||
        audioClipEnd != other.audioClipEnd ||
        videoClips.length != other.videoClips.length) {
      return false;
    }

    for (var i = 0; i < videoClips.length; i++) {
      final left = videoClips[i];
      final right = other.videoClips[i];
      if (left.start != right.start || left.end != right.end) return false;
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
