import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/shape_paths.dart';

/// How close a click must land to count as hitting an outline, in document
/// pixels, on top of half the element's own stroke width.
const double kHitTolerance = 4;

/// Whether ([x], [y]) hits [element].
///
/// Everything happens in document space. A rotated shape is tested by rotating
/// the *point* backwards about the shape's centre, which is cheaper and exact
/// compared with rotating the geometry.
bool hitTestElement(
  CanvasElement element,
  double x,
  double y, {
  double tolerance = kHitTolerance,
}) => switch (element) {
  Stroke() => _hitStroke(element, x, y, tolerance),
  Shape() => _hitShape(element, x, y, tolerance),
  // A text box is grabbable anywhere inside it: clicking the gaps between
  // glyphs must still select, and pick a caret position once editing.
  TextElement() => _hitText(element, x, y, tolerance),
};

/// Every element of [layers] under the point, topmost first.
///
/// Hidden layers are skipped: you cannot click what you cannot see.
List<CanvasElement> elementsAt(
  List<Layer> layers,
  double x,
  double y, {
  double tolerance = kHitTolerance,
}) {
  final hits = <CanvasElement>[];
  for (final layer in layers.reversed) {
    if (!layer.visible || layer.opacity == 0) continue;
    for (final element in layer.elements.reversed) {
      if (hitTestElement(element, x, y, tolerance: tolerance)) {
        hits.add(element);
      }
    }
  }
  return hits;
}

/// The topmost element under the point, or `null`.
CanvasElement? topmostElementAt(
  List<Layer> layers,
  double x,
  double y, {
  double tolerance = kHitTolerance,
}) {
  final hits = elementsAt(layers, x, y, tolerance: tolerance);
  return hits.isEmpty ? null : hits.first;
}

/// Elements of [layers] whose bounds lie wholly inside [marquee].
List<CanvasElement> elementsWithin(List<Layer> layers, Bounds marquee) => [
  for (final layer in layers)
    if (layer.visible && layer.opacity > 0)
      for (final element in layer.elements)
        if (_within(element.bounds, marquee)) element,
];

bool _within(Bounds? inner, Bounds outer) =>
    inner != null &&
    inner.left >= outer.left &&
    inner.right <= outer.right &&
    inner.top >= outer.top &&
    inner.bottom <= outer.bottom;

bool _hitStroke(Stroke stroke, double x, double y, double tolerance) {
  if (stroke.points.isEmpty) return false;
  final reach = tolerance + stroke.baseWidth / 2;

  if (stroke.points.length == 1) {
    return _distance(stroke.points.first.x, stroke.points.first.y, x, y) <=
        reach;
  }
  for (var i = 1; i < stroke.points.length; i++) {
    final a = stroke.points[i - 1];
    final b = stroke.points[i];
    if (_distanceToSegment(x, y, a.x, a.y, b.x, b.y) <= reach) return true;
  }
  return false;
}

bool _hitText(TextElement element, double x, double y, double tolerance) {
  final local = _unrotate(
    x,
    y,
    element.centerX,
    element.centerY,
    element.rotation,
  );
  return local.dx >= element.x - tolerance &&
      local.dx <= element.x + element.w + tolerance &&
      local.dy >= element.y - tolerance &&
      local.dy <= element.y + element.h + tolerance;
}

bool _hitShape(Shape shape, double x, double y, double tolerance) {
  final box = shape.normalized();
  final local = _unrotate(x, y, box.centerX, box.centerY, box.rotation);
  final rect = Rect.fromLTWH(box.x, box.y, box.w, box.h);
  final path = buildShapePath(box.type, rect, strokeWidth: box.strokeWidth);
  final reach = tolerance + box.strokeWidth / 2;

  // A filled, closed shape is grabbable anywhere inside it. Everything else is
  // grabbable only near its outline — you can click through the middle of an
  // unfilled rectangle, as every drawing tool lets you.
  if (box.isFilled && shapeTypeIsClosed(box.type)) {
    if (path.contains(Offset(local.dx, local.dy))) return true;
  }

  // Walk the outline. Path has no distance query, so sample it: at 2px steps a
  // 4px tolerance can never fall through the gap.
  for (final metric in path.computeMetrics()) {
    const step = 2.0;
    for (var d = 0.0; d <= metric.length; d += step) {
      final tangent = metric.getTangentForOffset(d);
      if (tangent == null) continue;
      final p = tangent.position;
      if (_distance(p.dx, p.dy, local.dx, local.dy) <= reach) return true;
    }
  }
  return false;
}

/// [x], [y] rotated by `-rotation` about ([cx], [cy]).
Offset _unrotate(double x, double y, double cx, double cy, double rotation) {
  if (rotation == 0) return Offset(x, y);
  final cos = math.cos(-rotation);
  final sin = math.sin(-rotation);
  final dx = x - cx;
  final dy = y - cy;
  return Offset(cx + dx * cos - dy * sin, cy + dx * sin + dy * cos);
}

double _distance(double ax, double ay, double bx, double by) =>
    math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));

double _distanceToSegment(
  double px,
  double py,
  double ax,
  double ay,
  double bx,
  double by,
) {
  final dx = bx - ax;
  final dy = by - ay;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared < 1e-12) return _distance(px, py, ax, ay);

  final t = (((px - ax) * dx + (py - ay) * dy) / lengthSquared).clamp(0.0, 1.0);
  return _distance(px, py, ax + t * dx, ay + t * dy);
}
