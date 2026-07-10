import 'dart:math' as math;
import 'dart:ui' show Offset, Path, PathMetric, Rect;

import 'package:inkpad/domain/models/models.dart';

/// Arrow head length, as a multiple of the stroke width.
const double kArrowHeadScale = 6;

/// The outline of a shape, in its own unrotated coordinates.
///
/// [rect] is the normalized box. [strokeWidth] only matters for the arrow,
/// whose head is sized relative to the line that carries it.
Path buildShapePath(ShapeType type, Rect rect, {double strokeWidth = 1}) {
  switch (type) {
    case ShapeType.rectangle:
      return Path()..addRect(rect);

    case ShapeType.ellipse:
      return Path()..addOval(rect);

    case ShapeType.line:
      return Path()
        ..moveTo(rect.left, rect.top)
        ..lineTo(rect.right, rect.bottom);

    case ShapeType.diamond:
      return Path()
        ..moveTo(rect.center.dx, rect.top)
        ..lineTo(rect.right, rect.center.dy)
        ..lineTo(rect.center.dx, rect.bottom)
        ..lineTo(rect.left, rect.center.dy)
        ..close();

    case ShapeType.arrow:
      return _arrowPath(rect, strokeWidth);
  }
}

/// A shaft from the box's top-left to its bottom-right, with a head on the end.
Path _arrowPath(Rect rect, double strokeWidth) {
  final path = Path()
    ..moveTo(rect.left, rect.top)
    ..lineTo(rect.right, rect.bottom);
  return path..addPath(arrowHeadPath(rect, strokeWidth), Offset.zero);
}

/// The two barbs at the end of an arrow, with no shaft.
///
/// Shared with the rough renderer, whose shaft wobbles while its head stays
/// crisp — a wobbly head stops reading as a head.
Path arrowHeadPath(Rect rect, double strokeWidth) =>
    arrowHeadAt(rect.topLeft, rect.bottomRight, strokeWidth);

/// The barbs at [end] for a shaft running [start] → [end].
///
/// Takes points, not a `Rect`: a `Rect` normalizes its corners, so an arrow
/// pointing up-left would come out of it pointing down-right. A connector runs
/// in every direction.
Path arrowHeadAt(Offset start, Offset end, double strokeWidth) {
  final path = Path();

  final dx = end.dx - start.dx;
  final dy = end.dy - start.dy;
  final length = math.sqrt(dx * dx + dy * dy);
  if (length < 1e-9) return path;

  // The head never grows longer than the shaft, or a tiny arrow turns into a
  // pair of crossed sticks.
  final head = math.min(strokeWidth * kArrowHeadScale, length / 2);
  final ux = dx / length;
  final uy = dy / length;

  const spread = math.pi / 7;
  final cosS = math.cos(spread);
  final sinS = math.sin(spread);

  // Rotate the reversed direction by ±spread and step `head` along it.
  for (final sign in [1.0, -1.0]) {
    final rx = -ux * cosS - sign * -uy * sinS;
    final ry = -uy * cosS + sign * -ux * sinS;
    path
      ..moveTo(end.dx, end.dy)
      ..lineTo(end.dx + rx * head, end.dy + ry * head);
  }
  return path;
}

/// Whether [type] encloses an area that can be filled.
///
/// A line and an arrow do not, so a "filled" one is still only its outline.
bool shapeTypeIsClosed(ShapeType type) => switch (type) {
  ShapeType.rectangle || ShapeType.ellipse || ShapeType.diamond => true,
  ShapeType.line || ShapeType.arrow => false,
};

/// Dash pattern for a stroke style, in multiples of the stroke width.
/// `null` for a solid line, which is drawn as-is.
List<double>? dashPatternFor(StrokeStyle style) => switch (style) {
  StrokeStyle.solid => null,
  StrokeStyle.dashed => const [3, 2],
  StrokeStyle.dotted => const [0.1, 1.6],
};

/// [source] broken into dashes, so it can be stroked as a dashed line.
///
/// Lengths in [pattern] are multiples of [strokeWidth]. A degenerate pattern
/// returns the path untouched rather than looping forever.
Path dashPath(Path source, List<double> pattern, double strokeWidth) {
  final lengths = [for (final p in pattern) p * strokeWidth];
  if (lengths.isEmpty || lengths.every((l) => l <= 0)) return source;

  final dashed = Path();
  for (final PathMetric metric in source.computeMetrics()) {
    var distance = 0.0;
    var index = 0;
    var drawing = true;

    while (distance < metric.length) {
      final step = lengths[index % lengths.length];
      final next = math.min(distance + step, metric.length);
      if (drawing && step > 0) {
        dashed.addPath(metric.extractPath(distance, next), Offset.zero);
      }
      distance = next;
      drawing = !drawing;
      index++;
    }
  }
  return dashed;
}
