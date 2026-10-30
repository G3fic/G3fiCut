import 'timeline_history.dart';

class TimelineEditing {
  static const double minimumClipLength = 0.08;
  static const double epsilon = 0.001;

  static List<TimelineClipRange> splitAt(List<TimelineClipRange> clips, int index, double sequenceTime) {
    _requireIndex(clips, index);
    final clip = clips[index];
    final offset = sequenceTime - clip.timelineStart;
    if (offset <= minimumClipLength || offset >= clip.length - minimumClipLength) {
      throw ArgumentError('Курсор должен находиться внутри клипа.');
    }
    final sourceCut = clip.start + offset;
    final result = List<TimelineClipRange>.of(clips);
    result[index] = TimelineClipRange(clip.start, sourceCut, timelineStart: clip.timelineStart);
    result.insert(index + 1, TimelineClipRange(sourceCut, clip.end, timelineStart: sequenceTime));
    return result;
  }

  static List<TimelineClipRange> duplicateAfter(List<TimelineClipRange> clips, int index) {
    _requireIndex(clips, index);
    final selected = clips[index];
    final insertAt = selected.timelineEnd;
    final result = <TimelineClipRange>[];
    for (var i = 0; i < clips.length; i++) {
      final clip = clips[i];
      if (i != index && clip.timelineStart >= insertAt - epsilon) {
        result.add(_copyAt(clip, clip.timelineStart + selected.length));
      } else {
        result.add(clip);
      }
    }
    result.add(TimelineClipRange(selected.start, selected.end, timelineStart: insertAt));
    result.sort(_compare);
    return result;
  }

  static List<TimelineClipRange> moveInsert(List<TimelineClipRange> clips, int index, double requestedStart) {
    _requireIndex(clips, index);
    final moving = clips[index];
    final others = <TimelineClipRange>[
      for (var i = 0; i < clips.length; i++)
        if (i != index) clips[i],
    ]..sort(_compare);
    final desired = requestedStart < 0 ? 0.0 : requestedStart;
    var insertionIndex = 0;
    while (insertionIndex < others.length) {
      final midpoint = others[insertionIndex].timelineStart + others[insertionIndex].length / 2;
      if (desired < midpoint) break;
      insertionIndex++;
    }
    final previousEnd = insertionIndex == 0 ? 0.0 : others[insertionIndex - 1].timelineEnd;
    final insertAt = desired < previousEnd ? previousEnd : desired;
    final shift = insertionIndex < others.length
        ? (insertAt + moving.length - others[insertionIndex].timelineStart).clamp(0.0, double.infinity).toDouble()
        : 0.0;
    for (var i = insertionIndex; i < others.length; i++) {
      others[i] = _copyAt(others[i], others[i].timelineStart + shift);
    }
    others.insert(insertionIndex, TimelineClipRange(moving.start, moving.end, timelineStart: insertAt));
    return others;
  }

  static List<TimelineClipRange> trimStartRipple(List<TimelineClipRange> clips, int index, double sequenceTime) {
    _requireIndex(clips, index);
    final selected = clips[index];
    final offset = sequenceTime - selected.timelineStart;
    if (offset <= 0 || offset >= selected.length - minimumClipLength) {
      throw ArgumentError('Курсор должен находиться внутри клипа.');
    }
    final result = List<TimelineClipRange>.of(clips);
    result[index] = TimelineClipRange(selected.start + offset, selected.end, timelineStart: selected.timelineStart);
    for (var i = index + 1; i < result.length; i++) {
      result[i] = _copyAt(result[i], result[i].timelineStart - offset);
    }
    return result;
  }

  static List<TimelineClipRange> trimEndRipple(List<TimelineClipRange> clips, int index, double sequenceTime) {
    _requireIndex(clips, index);
    final selected = clips[index];
    final newLength = sequenceTime - selected.timelineStart;
    if (newLength <= minimumClipLength || newLength >= selected.length) {
      throw ArgumentError('Курсор должен находиться внутри клипа.');
    }
    final removed = selected.length - newLength;
    final result = List<TimelineClipRange>.of(clips);
    result[index] = TimelineClipRange(selected.start, selected.start + newLength, timelineStart: selected.timelineStart);
    for (var i = index + 1; i < result.length; i++) {
      result[i] = _copyAt(result[i], result[i].timelineStart - removed);
    }
    return result;
  }

  static List<TimelineClipRange> rippleDelete(List<TimelineClipRange> clips, int index) {
    _requireIndex(clips, index);
    final removed = clips[index];
    final result = <TimelineClipRange>[];
    for (var i = 0; i < clips.length; i++) {
      if (i == index) continue;
      final clip = clips[i];
      result.add(clip.timelineStart >= removed.timelineEnd - epsilon
          ? _copyAt(clip, clip.timelineStart - removed.length)
          : clip);
    }
    result.sort(_compare);
    return result;
  }

  static List<TimelineClipRange> deleteLeaveGap(List<TimelineClipRange> clips, int index) {
    _requireIndex(clips, index);
    return List<TimelineClipRange>.of(clips)..removeAt(index);
  }

  static TimelineClipRange _copyAt(TimelineClipRange clip, double timelineStart) =>
      TimelineClipRange(clip.start, clip.end, timelineStart: timelineStart);

  static int _compare(TimelineClipRange a, TimelineClipRange b) =>
      a.timelineStart.compareTo(b.timelineStart);

  static void _requireIndex(List<TimelineClipRange> clips, int index) {
    if (index < 0 || index >= clips.length) throw RangeError.index(index, clips, 'index');
  }
}
