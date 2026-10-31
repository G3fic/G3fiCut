import 'package:flutter_test/flutter_test.dart';
import 'package:gifcut/canvas_snapping.dart';

void main() {
  group('CenterAxisSnapper', () {
    const snapper = CenterAxisSnapper();

    test('latches exactly to the center when inside the catch distance', () {
      final result = snapper.update(
        rawOffset: 12 / 800,
        canvasExtent: 800,
        wasSnapped: false,
      );

      expect(result.offset, 0);
      expect(result.isSnapped, isTrue);
    });

    test('does not snap when outside the catch distance', () {
      final result = snapper.update(
        rawOffset: 15 / 800,
        canvasExtent: 800,
        wasSnapped: false,
      );

      expect(result.offset, 15 / 800);
      expect(result.isSnapped, isFalse);
    });

    test('keeps snapping through the wider release distance', () {
      final result = snapper.update(
        rawOffset: 20 / 800,
        canvasExtent: 800,
        wasSnapped: true,
      );

      expect(result.offset, 0);
      expect(result.isSnapped, isTrue);
    });

    test('releases after the pointer moves beyond the release distance', () {
      final result = snapper.update(
        rawOffset: 25 / 800,
        canvasExtent: 800,
        wasSnapped: true,
      );

      expect(result.offset, 25 / 800);
      expect(result.isSnapped, isFalse);
    });

    test('does not snap with an invalid canvas extent', () {
      final result = snapper.update(
        rawOffset: 0,
        canvasExtent: 0,
        wasSnapped: false,
      );

      expect(result.offset, 0);
      expect(result.isSnapped, isFalse);
    });
  });
  group('AngleSnapper', () {
    const snapper = AngleSnapper(stepDegrees: 15, catchDistance: 3);

    test('snaps to the nearest 15-degree angle inside the catch distance', () {
      expect(snapper.snap(13), 15);
      expect(snapper.snap(1), 0);
    });

    test('leaves the angle unchanged outside the catch distance', () {
      expect(snapper.snap(10), 10);
    });

    test('respects the shared snapping toggle', () {
      expect(snapper.snap(13, enabled: false), 13);
    });

    test('handles angles across the 360-degree boundary', () {
      expect(snapper.snap(359), 360);
    });
  });

}
