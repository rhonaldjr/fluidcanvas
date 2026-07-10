import 'package:flutter/material.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/renderer/stroke_painter.dart';

/// Unpacks a 0xRRGGBBAA int, as stored on the models and in `.skd`, into a
/// Flutter [Color], which is ARGB.
Color colorFromRGBA(int rgba) => Color.fromARGB(
  rgba & 0xFF,
  (rgba >> 24) & 0xFF,
  (rgba >> 16) & 0xFF,
  (rgba >> 8) & 0xFF,
);

/// Paints every committed element of a document, bottom layer first.
///
/// Naive: it repaints the whole document on every change. Task 5.1 replaces
/// this with per-layer cached images, leaving only the in-progress stroke live.
class DocumentPainter extends CustomPainter {
  const DocumentPainter({required this.document, required this.scale});

  final SkdDocument document;

  /// Page screen size divided by document size.
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (scale <= 0) return;

    canvas.save();
    canvas.scale(scale);

    for (final layer in document.layers) {
      if (!layer.contributesPixels) continue;
      _paintLayer(canvas, layer);
    }

    canvas.restore();
  }

  void _paintLayer(Canvas canvas, Layer layer) {
    final translucent = layer.opacity < 1.0;
    if (translucent) {
      // Compositing the layer as a whole, rather than fading each element,
      // keeps overlapping strokes within it from showing through each other.
      canvas.saveLayer(
        null,
        Paint()..color = Color.fromARGB((layer.opacity * 255).round(), 0, 0, 0),
      );
    }

    for (final element in layer.elements) {
      switch (element) {
        case Stroke():
          _paintStroke(canvas, element);
        case Shape():
          // Task 8.2 renders shapes. Deliberately not a `default` case: the
          // sealed type must keep failing to compile when a variant is added.
          break;
      }
    }

    if (translucent) canvas.restore();
  }

  void _paintStroke(Canvas canvas, Stroke stroke) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..color = colorFromRGBA(stroke.colorRGBA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke.baseWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    if (stroke.points.length == 1) {
      final point = stroke.points.first;
      canvas.drawCircle(
        Offset(point.x, point.y),
        stroke.baseWidth / 2,
        paint..style = PaintingStyle.fill,
      );
    } else {
      canvas.drawPath(buildPolylinePath(stroke.points), paint);
    }
  }

  @override
  bool shouldRepaint(DocumentPainter old) =>
      // Documents are immutable, so a change means a new instance.
      !identical(old.document, document) || old.scale != scale;
}
