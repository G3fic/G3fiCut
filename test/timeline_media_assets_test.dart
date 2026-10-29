import 'package:flutter_test/flutter_test.dart';
import 'package:g3ficut/timeline_media_assets.dart';

void main() {
  group('thumbnailIndexForTime', () {
    test('returns -1 when no thumbnails are available', () {
      expect(thumbnailIndexForTime(timeSeconds: 0, durationSeconds: 10, thumbnailCount: 0), -1);
      expect(thumbnailIndexForTime(timeSeconds: 0, durationSeconds: 10, thumbnailCount: -2), -1);
    });

    test('maps first, middle and final source times to stable frame indices', () {
      expect(thumbnailIndexForTime(timeSeconds: 0, durationSeconds: 10, thumbnailCount: 10), 0);
      expect(thumbnailIndexForTime(timeSeconds: 5, durationSeconds: 10, thumbnailCount: 10), 5);
      expect(thumbnailIndexForTime(timeSeconds: 9.99, durationSeconds: 10, thumbnailCount: 10), 9);
      expect(thumbnailIndexForTime(timeSeconds: 10, durationSeconds: 10, thumbnailCount: 10), 9);
    });

    test('clamps negative and past-end time values', () {
      expect(thumbnailIndexForTime(timeSeconds: -8, durationSeconds: 8, thumbnailCount: 4), 0);
      expect(thumbnailIndexForTime(timeSeconds: 80, durationSeconds: 8, thumbnailCount: 4), 3);
    });

    test('handles zero or invalid duration defensively', () {
      expect(thumbnailIndexForTime(timeSeconds: 3, durationSeconds: 0, thumbnailCount: 12), 0);
      expect(thumbnailIndexForTime(timeSeconds: 3, durationSeconds: -1, thumbnailCount: 12), 0);
      expect(thumbnailIndexForTime(timeSeconds: 3, durationSeconds: double.infinity, thumbnailCount: 12), 0);
      expect(thumbnailIndexForTime(timeSeconds: double.nan, durationSeconds: 10, thumbnailCount: 12), 0);
      expect(thumbnailIndexForTime(timeSeconds: double.infinity, durationSeconds: 10, thumbnailCount: 12), 0);
    });

    test('does not produce indices outside the available list', () {
      expect(thumbnailIndexForTime(timeSeconds: 0.001, durationSeconds: 1000000, thumbnailCount: 1), 0);
      expect(thumbnailIndexForTime(timeSeconds: 12.5, durationSeconds: 7, thumbnailCount: 2), 1);
    });
  });
}