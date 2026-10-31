/// Snaps rotations to regular angular increments when they are close enough.
class AngleSnapper {
  const AngleSnapper({
    this.stepDegrees = 15,
    this.catchDistance = 3,
  })  : assert(stepDegrees > 0),
        assert(catchDistance >= 0);

  final double stepDegrees;
  final double catchDistance;

  double snap(double degrees, {bool enabled = true}) {
    if (!enabled || !degrees.isFinite || !stepDegrees.isFinite || stepDegrees <= 0) {
      return degrees;
    }

    final nearest = (degrees / stepDegrees).round() * stepDegrees;
    var difference = nearest - degrees;
    if (difference > 180) difference -= 360;
    if (difference < -180) difference += 360;
    return difference.abs() <= catchDistance ? degrees + difference : degrees;
  }
}

/// Hysteresis-based snapping of an object's center to one canvas axis.
class AxisSnapResult {
  const AxisSnapResult({required this.offset, required this.isSnapped});

  final double offset;
  final bool isSnapped;
}

class CenterAxisSnapper {
  const CenterAxisSnapper({
    this.catchDistance = 14,
    this.releaseDistance = 24,
  }) : assert(catchDistance > 0 && releaseDistance >= catchDistance);

  final double catchDistance;
  final double releaseDistance;

  AxisSnapResult update({
    required double rawOffset,
    required double canvasExtent,
    required bool wasSnapped,
  }) {
    if (!rawOffset.isFinite || !canvasExtent.isFinite || canvasExtent <= 0) {
      return AxisSnapResult(offset: rawOffset, isSnapped: false);
    }

    final distanceFromAxis = rawOffset * canvasExtent;
    final limit = wasSnapped ? releaseDistance : catchDistance;
    final snapped = distanceFromAxis.abs() <= limit;
    return AxisSnapResult(
      offset: snapped ? 0 : rawOffset,
      isSnapped: snapped,
    );
  }
}

/// A canvas guide that an object's edge or center can align with.
enum CanvasGuide { leading, center, trailing }

class CanvasGuideSnapResult {
  const CanvasGuideSnapResult({required this.offset, required this.guide});

  /// Normalized object-center offset from the canvas center.
  final double offset;
  final CanvasGuide? guide;

  bool get isSnapped => guide != null;
}

/// Snaps transformed objects to the canvas center and its four edges.
///
/// [objectExtent] is the object's rendered bounding-box size on the current
/// axis, including its scale and rotation. Offsets are normalized to the
/// canvas extent so this behaves identically for video and photo layers.
class CanvasGuideSnapper {
  const CanvasGuideSnapper({
    this.catchDistance = 14,
    this.releaseDistance = 24,
  }) : assert(catchDistance > 0 && releaseDistance >= catchDistance);

  final double catchDistance;
  final double releaseDistance;

  double _target(CanvasGuide guide, double halfExtent) => switch (guide) {
        CanvasGuide.leading => -0.5 + halfExtent,
        CanvasGuide.center => 0,
        CanvasGuide.trailing => 0.5 - halfExtent,
      };

  CanvasGuideSnapResult update({
    required double rawOffset,
    required double canvasExtent,
    required double objectExtent,
    CanvasGuide? previousGuide,
    bool enabled = true,
  }) {
    if (!enabled ||
        !rawOffset.isFinite ||
        !canvasExtent.isFinite ||
        canvasExtent <= 0 ||
        !objectExtent.isFinite ||
        objectExtent < 0) {
      return CanvasGuideSnapResult(offset: rawOffset, guide: null);
    }

    final halfExtent = objectExtent / (2 * canvasExtent);
    if (!halfExtent.isFinite) {
      return CanvasGuideSnapResult(offset: rawOffset, guide: null);
    }

    if (previousGuide != null) {
      final target = _target(previousGuide, halfExtent);
      if ((rawOffset - target).abs() * canvasExtent <= releaseDistance) {
        return CanvasGuideSnapResult(offset: target, guide: previousGuide);
      }
    }

    CanvasGuide? nearestGuide;
    var nearestTarget = rawOffset;
    var nearestDistance = double.infinity;
    for (final guide in CanvasGuide.values) {
      final target = _target(guide, halfExtent);
      final distance = (rawOffset - target).abs() * canvasExtent;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestTarget = target;
        nearestGuide = guide;
      }
    }

    if (nearestDistance <= catchDistance) {
      return CanvasGuideSnapResult(offset: nearestTarget, guide: nearestGuide);
    }
    return CanvasGuideSnapResult(offset: rawOffset, guide: null);
  }
}
