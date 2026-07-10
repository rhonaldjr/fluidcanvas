import 'dart:math' as math;

import 'package:inkpad/domain/models/models.dart';

/// Minimum gap between consecutive stroke points, in document pixels.
///
/// A 120Hz stylus barely moving still emits events; without a floor the stroke
/// accumulates thousands of coincident points, which cost memory, bloat the
/// `.skd` file, and make smoothing degenerate.
const double kMinPointDistance = 1.5;

/// Whether [candidate] is far enough from [previous] to be worth keeping.
///
/// Distances are in document space, so thinning behaves the same at every zoom.
/// Compares squared distances to avoid a square root per pointer event.
bool isFarEnough(
  StrokePoint previous,
  StrokePoint candidate, {
  double minDistance = kMinPointDistance,
}) {
  assert(minDistance >= 0, 'minDistance must not be negative');
  final dx = candidate.x - previous.x;
  final dy = candidate.y - previous.y;
  return dx * dx + dy * dy >= minDistance * minDistance;
}

/// Drops points closer than [minDistance] to the last point kept.
///
/// Always keeps the first point. Measures against the last *kept* point, not
/// the previous input point: otherwise a slow drag of many sub-threshold steps
/// would be thinned away entirely, and the stroke would never advance.
List<StrokePoint> thinPoints(
  List<StrokePoint> points, {
  double minDistance = kMinPointDistance,
}) {
  if (points.length < 2) return List.of(points);

  final kept = <StrokePoint>[points.first];
  for (final point in points.skip(1)) {
    if (isFarEnough(kept.last, point, minDistance: minDistance)) {
      kept.add(point);
    }
  }
  return kept;
}

/// Euclidean distance between two points, in document pixels.
double distanceBetween(StrokePoint a, StrokePoint b) =>
    math.sqrt(math.pow(b.x - a.x, 2) + math.pow(b.y - a.y, 2));
