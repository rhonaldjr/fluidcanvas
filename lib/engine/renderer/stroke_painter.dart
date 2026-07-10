import 'package:flutter/material.dart';
import 'package:inkpad/domain/models/models.dart';

/// Fixed appearance of a stroke until task 4.2 introduces brush settings.
///
/// Packed 0xRRGGBBAA, as the models and `.skd` store colour.
const int kDefaultStrokeColorRGBA = 0x1B1B1FFF;
const double kDefaultStrokeWidth = 4;

/// The same colour as a Flutter [Color], for painting.
const Color kInProgressStrokeColor = Color(0xFF1B1B1F);
const double kInProgressStrokeWidth = kDefaultStrokeWidth;

/// A polyline through [points], in document space.
///
/// Returns an empty path for no points. A single point produces a path with no
/// segments, which strokes to nothing — [InProgressStrokePainter] draws a dot
/// for that case instead, so a tap leaves a mark.
Path buildPolylinePath(List<StrokePoint> points) {
  final path = Path();
  if (points.isEmpty) return path;

  path.moveTo(points.first.x, points.first.y);
  for (final point in points.skip(1)) {
    path.lineTo(point.x, point.y);
  }
  return path;
}

/// Paints the stroke currently under the pointer.
///
/// Points arrive in document space; the canvas is scaled so that stroke width
/// is expressed in document units too, and scales with the page.
class InProgressStrokePainter extends CustomPainter {
  const InProgressStrokePainter({
    required this.points,
    required this.scale,
    this.color = kInProgressStrokeColor,
    this.strokeWidth = kInProgressStrokeWidth,
  });

  final List<StrokePoint> points;

  /// Page screen size divided by document size.
  final double scale;

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || scale <= 0) return;

    canvas.save();
    canvas.scale(scale);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    if (points.length == 1) {
      // A stroked path with no segments paints nothing, so a tap would vanish.
      canvas.drawCircle(
        Offset(points.first.x, points.first.y),
        strokeWidth / 2,
        paint..style = PaintingStyle.fill,
      );
    } else {
      canvas.drawPath(buildPolylinePath(points), paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(InProgressStrokePainter old) =>
      // The notifier publishes a new list per point, so identity is enough and
      // avoids walking the points on every frame.
      !identical(old.points, points) ||
      old.scale != scale ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
