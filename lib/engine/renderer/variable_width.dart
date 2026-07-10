import 'dart:math' as math;
import 'dart:ui' show Offset, Path, PathOperation, Rect;

import 'package:inkpad/domain/models/models.dart';

/// Width at zero pressure, as a fraction of the stroke's base width.
///
/// Not zero: a stylus reporting no pressure at the very start of a stroke
/// should still leave a mark, and a hairline that tapers to nothing looks like
/// a dropout rather than a light touch.
const double kPressureMinFactor = 0.35;

/// Stroke width at [pressure], in document pixels.
///
/// Linear between `baseWidth * minFactor` at zero pressure and `baseWidth` at
/// full pressure. Mice report full pressure, so they draw at [baseWidth].
double widthForPressure(
  double baseWidth,
  double pressure, {
  double minFactor = kPressureMinFactor,
}) {
  assert(baseWidth > 0, 'baseWidth must be positive');
  assert(minFactor > 0 && minFactor <= 1, 'minFactor must be in (0, 1]');
  assert(pressure >= 0 && pressure <= 1, 'pressure must be in 0..1');
  return baseWidth * (minFactor + (1 - minFactor) * pressure);
}

/// The outline of a variable-width stroke, ready to be *filled*.
///
/// Walks up one side of the centreline offsetting each point along its normal
/// by half its pressure-derived width, then back down the other, and caps both
/// ends with a disc. Filling this beats stroking a polyline, which can only
/// carry one width for the whole path.
///
/// Returns an empty path for no points, and a disc for one.
Path buildVariableWidthPath(
  List<StrokePoint> points,
  double baseWidth, {
  double minFactor = kPressureMinFactor,
}) {
  final path = Path();
  if (points.isEmpty) return path;

  double halfWidthAt(int i) =>
      widthForPressure(baseWidth, points[i].pressure, minFactor: minFactor) / 2;

  if (points.length == 1) {
    return path..addOval(
      Rect.fromCircle(
        center: Offset(points.first.x, points.first.y),
        radius: halfWidthAt(0),
      ),
    );
  }

  final normals = _normals(points);
  final left = <Offset>[];
  final right = <Offset>[];

  for (var i = 0; i < points.length; i++) {
    final centre = Offset(points[i].x, points[i].y);
    final offset = normals[i] * halfWidthAt(i);
    left.add(centre + offset);
    right.add(centre - offset);
  }

  path.moveTo(left.first.dx, left.first.dy);
  for (final point in left.skip(1)) {
    path.lineTo(point.dx, point.dy);
  }
  for (final point in right.reversed) {
    path.lineTo(point.dx, point.dy);
  }
  path.close();

  // Round caps, unioned rather than merely added as subpaths. The ribbon and
  // the discs can wind in opposite directions, and a non-zero fill then cancels
  // them where they overlap, leaving a crescent-shaped hole at each endpoint.
  final caps = Path()
    ..addOval(
      Rect.fromCircle(
        center: Offset(points.first.x, points.first.y),
        radius: halfWidthAt(0),
      ),
    )
    ..addOval(
      Rect.fromCircle(
        center: Offset(points.last.x, points.last.y),
        radius: halfWidthAt(points.length - 1),
      ),
    );

  return Path.combine(PathOperation.union, path, caps);
}

/// Unit normal at each point: perpendicular to the local tangent.
///
/// Interior points average their two adjacent segments so the ribbon does not
/// kink. Coincident points have no direction of their own and inherit the last
/// usable normal rather than producing NaNs.
List<Offset> _normals(List<StrokePoint> points) {
  final normals = <Offset>[];
  var previous = const Offset(0, -1);

  for (var i = 0; i < points.length; i++) {
    final before = i == 0 ? points[i] : points[i - 1];
    final after = i == points.length - 1 ? points[i] : points[i + 1];

    final dx = after.x - before.x;
    final dy = after.y - before.y;
    final length = math.sqrt(dx * dx + dy * dy);

    if (length < 1e-9) {
      normals.add(previous);
    } else {
      previous = Offset(-dy / length, dx / length);
      normals.add(previous);
    }
  }
  return normals;
}
