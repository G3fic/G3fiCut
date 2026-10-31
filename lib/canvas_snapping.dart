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
