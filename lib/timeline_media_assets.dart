/// Maps a source timestamp to the nearest thumbnail bucket for a cached strip.
///
/// Returns -1 when [thumbnailCount] is zero or negative. Invalid timestamps or
/// unknown durations fall back to the first available frame. Values outside the
/// source duration are clamped so callers never index outside the cache.
int thumbnailIndexForTime({
  required double timeSeconds,
  required double durationSeconds,
  required int thumbnailCount,
}) {
  if (thumbnailCount <= 0) return -1;
  if (!timeSeconds.isFinite ||
      !durationSeconds.isFinite ||
      durationSeconds <= 0) {
    return 0;
  }
  final ratio = (timeSeconds / durationSeconds).clamp(0.0, 1.0);
  final index = (ratio * thumbnailCount).floor();
  return index.clamp(0, thumbnailCount - 1).toInt();
}