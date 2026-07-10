import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:inkpad/domain/models/models.dart';

/// Radius of a resize handle, in **screen** pixels: handles stay grabbable at
/// every zoom, so they are not measured in document space.
const double kHandleRadius = 5;

/// How far above the box the rotation handle floats, in screen pixels.
const double kRotateHandleGap = 28;

/// A corner or edge of the selection box.
enum Handle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
  rotate;

  bool get isCorner =>
      this == topLeft ||
      this == topRight ||
      this == bottomRight ||
      this == bottomLeft;

  /// An edge handle changes one axis of the box. A corner scales both.
  bool get isEdge =>
      this == top || this == bottom || this == left || this == right;

  bool get changesWidth => isCorner || this == left || this == right;
  bool get changesHeight => isCorner || this == top || this == bottom;
}

/// The point a handle sits on, in document space.
Offset handlePosition(Handle handle, Bounds box, double scale) =>
    switch (handle) {
      Handle.topLeft => Offset(box.left, box.top),
      Handle.top => Offset(box.centerX, box.top),
      Handle.topRight => Offset(box.right, box.top),
      Handle.right => Offset(box.right, box.centerY),
      Handle.bottomRight => Offset(box.right, box.bottom),
      Handle.bottom => Offset(box.centerX, box.bottom),
      Handle.bottomLeft => Offset(box.left, box.bottom),
      Handle.left => Offset(box.left, box.centerY),
      // The gap is in screen pixels, so it does not grow with the page.
      Handle.rotate => Offset(box.centerX, box.top - kRotateHandleGap / scale),
    };

/// The corner diagonally opposite [handle] — the point a resize drag pins.
Offset anchorFor(Handle handle, Bounds box) => switch (handle) {
  Handle.topLeft => Offset(box.right, box.bottom),
  Handle.topRight => Offset(box.left, box.bottom),
  Handle.bottomRight => Offset(box.left, box.top),
  Handle.bottomLeft => Offset(box.right, box.top),
  Handle.top => Offset(box.centerX, box.bottom),
  Handle.bottom => Offset(box.centerX, box.top),
  Handle.left => Offset(box.right, box.centerY),
  Handle.right => Offset(box.left, box.centerY),
  Handle.rotate => Offset(box.centerX, box.centerY),
};

/// The handle within grabbing distance of ([x], [y]) in document space, or
/// `null`.
Handle? handleAt(Bounds box, double x, double y, double scale) {
  final reach = (kHandleRadius + 3) / scale;
  for (final handle in Handle.values) {
    final p = handlePosition(handle, box, scale);
    if ((p.dx - x).abs() <= reach && (p.dy - y).abs() <= reach) return handle;
  }
  return null;
}

/// The factor a **corner** drag implies, given where the pointer is now.
///
/// Measured along the diagonal from the pinned [anchor], so a corner scales
/// uniformly and a shape never shears. Clamped away from zero: a selection
/// scaled to nothing could never be grabbed again.
double resizeFactor({
  required Offset anchor,
  required Offset start,
  required Offset current,
}) {
  final was = (start - anchor).distance;
  if (was < 1e-6) return 1;
  final now = (current - anchor).distance;
  return math.max(now / was, 0.01);
}

/// Smallest box an edge drag will leave, in document pixels.
const double kMinBoxSize = 8;

/// The box an **edge** drag implies: one axis moves, the other is untouched.
///
/// This is what lets a text box be widened without magnifying its text — the
/// font size is unchanged, so the text simply rewraps. A corner drag scales
/// both axes and the font with them.
Bounds resizeBox(Bounds box, Handle handle, Offset current) {
  var left = box.left;
  var top = box.top;
  var right = box.right;
  var bottom = box.bottom;

  switch (handle) {
    case Handle.left:
      left = math.min(current.dx, right - kMinBoxSize);
    case Handle.right:
      right = math.max(current.dx, left + kMinBoxSize);
    case Handle.top:
      top = math.min(current.dy, bottom - kMinBoxSize);
    case Handle.bottom:
      bottom = math.max(current.dy, top + kMinBoxSize);
    case Handle.topLeft:
    case Handle.topRight:
    case Handle.bottomRight:
    case Handle.bottomLeft:
    case Handle.rotate:
      break;
  }
  return Bounds(left: left, top: top, right: right, bottom: bottom);
}

/// Draws the selection box, its handles, and the rotation stalk.
///
/// Handles are drawn at a constant *screen* size by undoing the page scale, so
/// they stay the same size to grab however far the page is zoomed.
class SelectionOverlayPainter extends CustomPainter {
  const SelectionOverlayPainter({
    required this.box,
    required this.scale,
    required this.color,
    this.marquee,
    this.origin = Offset.zero,
  });

  /// The selection box in document space, or `null` when nothing is selected.
  final Bounds? box;

  final double scale;
  final Color color;

  /// The rubber-band rectangle being dragged, in document space.
  final Bounds? marquee;

  /// Where document (0, 0) sits in this painter's box. Zero for a bounded page
  /// (the painter fills the page); the pan offset for an infinite canvas.
  final Offset origin;

  @override
  void paint(Canvas canvas, Size size) {
    if (scale <= 0) return;
    canvas.save();
    canvas
      ..translate(origin.dx, origin.dy)
      ..scale(scale);

    if (marquee != null) _paintMarquee(canvas, marquee!);
    if (box != null) _paintSelection(canvas, box!);

    canvas.restore();
  }

  void _paintMarquee(Canvas canvas, Bounds m) {
    final rect = Rect.fromLTRB(m.left, m.top, m.right, m.bottom);
    canvas
      ..drawRect(rect, Paint()..color = color.withValues(alpha: 0.08))
      ..drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 / scale,
      );
  }

  void _paintSelection(Canvas canvas, Bounds b) {
    final rect = Rect.fromLTRB(b.left, b.top, b.right, b.bottom);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / scale;

    canvas
      ..drawRect(rect, line)
      ..drawLine(
        Offset(b.centerX, b.top),
        handlePosition(Handle.rotate, b, scale),
        line,
      );

    final fill = Paint()..color = Colors.white;
    for (final handle in Handle.values) {
      final p = handlePosition(handle, b, scale);
      final r = kHandleRadius / scale;
      if (handle == Handle.rotate) {
        canvas
          ..drawCircle(p, r, fill)
          ..drawCircle(p, r, line);
      } else {
        final square = Rect.fromCenter(center: p, width: r * 2, height: r * 2);
        canvas
          ..drawRect(square, fill)
          ..drawRect(square, line);
      }
    }
  }

  @override
  bool shouldRepaint(SelectionOverlayPainter old) =>
      old.box != box ||
      old.marquee != marquee ||
      old.scale != scale ||
      old.color != color ||
      old.origin != origin;
}
