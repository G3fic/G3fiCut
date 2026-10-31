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

  group('Right-angle rotation snapping', () {
    const snapper = AngleSnapper(stepDegrees: 90, catchDistance: 5);

    test('snaps close rotations to horizontal and vertical orientations', () {
      expect(snapper.snap(87), 90);
      expect(snapper.snap(178), 180);
      expect(snapper.snap(271), 270);
      expect(snapper.snap(359), 360);
    });

    test('does not snap rotations outside the right-angle catch distance', () {
      expect(snapper.snap(84), 84);
      expect(snapper.snap(96), 96);
    });
  });


  group('CanvasGuideSnapper', () {
    const snapper = CanvasGuideSnapper();

    test('snaps a photo center to the canvas center', () {
      final result = snapper.update(
        rawOffset: 10 / 800,
        canvasExtent: 800,
        objectExtent: 180,
      );
      expect(result.offset, 0);
      expect(result.guide, CanvasGuide.center);
    });

    test('snaps an object's leading edge to the canvas edge', () {
      const halfExtent = 90.0;
      final target = -0.5 + halfExtent / 800;
      final result = snapper.update(
        rawOffset: target + 8 / 800,
        canvasExtent: 800,
        objectExtent: halfExtent * 2,
      );
      expect(result.offset, closeTo(target, 0.000001));
      expect(result.guide, CanvasGuide.leading);
    });

    test('snaps the trailing edge of a layer', () {
      const halfExtent = 90.0;
      final target = 0.5 - halfExtent / 800;
      final result = snapper.update(
        rawOffset: target - 6 / 800,
        canvasExtent: 800,
        objectExtent: halfExtent * 2,
      );
      expect(result.offset, closeTo(target, 0.000001));
      expect(result.guide, CanvasGuide.trailing);
    });

    test('keeps the previous guide through the release distance', () {
      final result = snapper.update(
        rawOffset: 18 / 800,
        canvasExtent: 800,
        objectExtent: 800,
        previousGuide: CanvasGuide.center,
      );
      expect(result.offset, 0);
      expect(result.guide, CanvasGuide.center);
    });

    test('does not snap when the shared snapping toggle is disabled', () {
      final result = snapper.update(
        rawOffset: 3 / 800,
        canvasExtent: 800,
        objectExtent: 180,
        enabled: false,
      );
      expect(result.offset, 3 / 800);
      expect(result.guide, isNull);
    });
  });

}
