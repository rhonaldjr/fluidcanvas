import 'dart:math' as math;
import 'dart:ui' show Offset, Path, Rect;

import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/shape_paths.dart';

/// How many times a rough outline is drawn over itself. Two passes read as a
/// pen gone round twice; three is scribble.
const int kRoughPasses = 2;

/// How far a point may wander, as a fraction of the shorter side of the box.
///
/// Also capped in absolute terms: a 2000px rectangle should look hand-drawn,
/// not exploded.
const double kRoughness = 0.012;
const double kMaxRoughOffset = 6;

/// Points sampled along each edge. Fewer reads as a polygon; more as a tremor.
const int kRoughSegments = 6;

/// A deterministic value noise generator.
///
/// Not `dart:math`'s [math.Random]: the wobble must be a pure function of
/// `(seed, which point)`, so a shape draws identically on every machine, on
/// every repaint, and — crucially — after being resized. A sequential PRNG
/// would reshuffle the moment a segment count changed.
///
/// This is the classic integer hash: multiply, xor-shift, multiply. Any decent
/// avalanche would do; what matters is that it is stateless and stable.
double roughNoise(int seed, int index) {
  var h = seed ^ (index * 0x9E3779B1);
  h = (h ^ (h >>> 16)) * 0x85EBCA6B;
  h &= 0xFFFFFFFF;
  h = (h ^ (h >>> 13)) * 0xC2B2AE35;
  h &= 0xFFFFFFFF;
  h = h ^ (h >>> 16);
  // Into [-1, 1].
  return (h & 0xFFFF) / 0x7FFF - 1;
}

/// How far points wander for a box of this size.
double roughOffsetFor(Rect rect) {
  final shorter = math.min(rect.width.abs(), rect.height.abs());
  return math.min(shorter * kRoughness, kMaxRoughOffset);
}

/// [point] nudged by the noise at [index].
///
/// Two independent noise lookups per point, one per axis, so a point can move
/// diagonally rather than only along `y = x`.
Offset _jitter(Offset point, int seed, int index, double amount) => Offset(
  point.dx + roughNoise(seed, index * 2) * amount,
  point.dy + roughNoise(seed, index * 2 + 1) * amount,
);

/// A hand-drawn version of [type] filling [rect], seeded by [seed].
///
/// Returns [kRoughPasses] overlapping subpaths in one [Path]: drawing the same
/// outline twice with different jitter is what makes it read as pen on paper.
/// The endpoints of a closed shape are deliberately left slightly open, the way
/// a hand does not quite return to where it started.
///
/// Pure: same inputs, same path, forever. Hit-testing ignores this entirely and
/// keeps using the parametric outline — you select the rectangle you meant to
/// draw, not the wobble you got.
Path buildRoughPath(
  ShapeType type,
  Rect rect, {
  required int seed,
  double strokeWidth = 1,
}) {
  final amount = roughOffsetFor(rect);
  if (amount <= 0) return buildShapePath(type, rect, strokeWidth: strokeWidth);

  final path = Path();
  for (var pass = 0; pass < kRoughPasses; pass++) {
    // A different corner of the noise field per pass, so the two strokes do
    // not lie on top of each other.
    final passSeed = seed ^ (0x5BF03635 * (pass + 1));
    _addRoughPass(path, type, rect, passSeed, amount, strokeWidth);
  }
  return path;
}

void _addRoughPass(
  Path path,
  ShapeType type,
  Rect rect,
  int seed,
  double amount,
  double strokeWidth,
) {
  switch (type) {
    case ShapeType.rectangle:
      _roughPolygon(
        path,
        [rect.topLeft, rect.topRight, rect.bottomRight, rect.bottomLeft],
        seed,
        amount,
        closed: true,
      );

    case ShapeType.diamond:
      _roughPolygon(
        path,
        [
          Offset(rect.center.dx, rect.top),
          Offset(rect.right, rect.center.dy),
          Offset(rect.center.dx, rect.bottom),
          Offset(rect.left, rect.center.dy),
        ],
        seed,
        amount,
        closed: true,
      );

    case ShapeType.ellipse:
      _roughEllipse(path, rect, seed, amount);

    case ShapeType.line:
      _roughEdge(path, rect.topLeft, rect.bottomRight, seed, 0, amount);

    case ShapeType.arrow:
      // The shaft wobbles; the head stays crisp, or it stops reading as a head.
      _roughEdge(path, rect.topLeft, rect.bottomRight, seed, 0, amount);
      path.addPath(arrowHeadPath(rect, strokeWidth), Offset.zero);
  }
}

/// Walks the polygon, wobbling every sampled point along the way.
void _roughPolygon(
  Path path,
  List<Offset> corners,
  int seed,
  double amount, {
  required bool closed,
}) {
  final edges = closed ? corners.length : corners.length - 1;
  for (var i = 0; i < edges; i++) {
    final from = corners[i];
    final to = corners[(i + 1) % corners.length];
    _roughEdge(path, from, to, seed, i * (kRoughSegments + 1), amount);
  }
}

/// One wobbly edge, as its own subpath.
///
/// Each edge is a separate subpath rather than a continuous outline: a hand
/// lifts the pen at the corners, and a shared corner point would have to agree
/// with both edges' noise.
void _roughEdge(
  Path path,
  Offset from,
  Offset to,
  int seed,
  int indexBase,
  double amount,
) {
  path.moveTo(from.dx, from.dy);
  for (var i = 1; i <= kRoughSegments; i++) {
    final t = i / kRoughSegments;
    final point = Offset.lerp(from, to, t)!;
    // The endpoint wanders less: corners should still look like corners.
    final scale = i == kRoughSegments ? 0.4 : 1.0;
    final wobbled = _jitter(point, seed, indexBase + i, amount * scale);
    path.lineTo(wobbled.dx, wobbled.dy);
  }
}

/// An ellipse sampled at [kRoughSegments] × 4 points, each nudged outward or
/// inward, closed back onto its first point.
void _roughEllipse(Path path, Rect rect, int seed, double amount) {
  final steps = kRoughSegments * 4;
  final cx = rect.center.dx;
  final cy = rect.center.dy;
  final rx = rect.width / 2;
  final ry = rect.height / 2;

  Offset at(int i) {
    final angle = i / steps * 2 * math.pi;
    final point = Offset(cx + rx * math.cos(angle), cy + ry * math.sin(angle));
    return _jitter(point, seed, i, amount);
  }

  final first = at(0);
  path.moveTo(first.dx, first.dy);
  for (var i = 1; i <= steps; i++) {
    final point = at(i % steps);
    path.lineTo(point.dx, point.dy);
  }
  path.close();
}
