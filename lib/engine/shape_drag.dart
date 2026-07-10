import 'dart:math' as math;

import 'package:inkpad/domain/models/models.dart';

/// The box a drag from [anchor] to [current] describes.
///
/// [square] constrains it to equal extents — a square, a circle, a 45° line.
/// [fromCenter] treats [anchor] as the centre rather than a corner.
///
/// Extents may come back negative: the drag can run right-to-left. Callers
/// persist `normalized()` shapes; only the live preview sees the raw sign.
({double x, double y, double w, double h}) dragBox({
  required StrokePoint anchor,
  required StrokePoint current,
  bool square = false,
  bool fromCenter = false,
}) {
  var dx = current.x - anchor.x;
  var dy = current.y - anchor.y;

  if (square) {
    // The larger extent wins, so the box never collapses while you drag.
    final size = math.max(dx.abs(), dy.abs());
    dx = dx.isNegative ? -size : size;
    dy = dy.isNegative ? -size : size;
  }

  if (fromCenter) {
    return (x: anchor.x - dx, y: anchor.y - dy, w: dx * 2, h: dy * 2);
  }
  return (x: anchor.x, y: anchor.y, w: dx, h: dy);
}

/// The shape a drag describes, in document space.
Shape shapeFromDrag({
  required String id,
  required ShapeType type,
  required StrokePoint anchor,
  required StrokePoint current,
  required int strokeColorRGBA,
  required int fillColorRGBA,
  required double strokeWidth,
  required StrokeStyle strokeStyle,
  bool square = false,
  bool fromCenter = false,
}) {
  final box = dragBox(
    anchor: anchor,
    current: current,
    square: square,
    fromCenter: fromCenter,
  );
  return Shape(
    id: id,
    type: type,
    x: box.x,
    y: box.y,
    w: box.w,
    h: box.h,
    strokeColorRGBA: strokeColorRGBA,
    fillColorRGBA: fillColorRGBA,
    strokeWidth: strokeWidth,
    strokeStyle: strokeStyle,
  );
}
