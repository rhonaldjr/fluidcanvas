import 'package:flutter/material.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/renderer/variable_width.dart';

/// Unpacks a 0xRRGGBBAA int, as stored on the models and in `.skd`, into a
/// Flutter [Color], which is ARGB.
Color colorFromRGBA(int rgba) => Color.fromARGB(
  rgba & 0xFF,
  (rgba >> 24) & 0xFF,
  (rgba >> 16) & 0xFF,
  (rgba >> 8) & 0xFF,
);

/// Paints every committed element of a document, bottom layer first, plus the
/// stroke currently under the pointer.
///
/// The live stroke is painted *inside* its layer rather than on top of
/// everything. That is what makes the eraser correct: `BlendMode.clear` must
/// only reach the layer it is drawn into, and a stroke painted over the whole
/// document would punch through every layer beneath.
///
/// Naive: it repaints the whole document on every pointer event. Task 5.1
/// replaces this with per-layer cached images, leaving only the active layer
/// live.
class DocumentPainter extends CustomPainter {
  const DocumentPainter({
    required this.document,
    required this.scale,
    this.liveStroke,
    this.liveLayerId,
  });

  final SkdDocument document;

  /// Page screen size divided by document size.
  final double scale;

  /// The stroke being drawn right now, or `null` between strokes.
  final Stroke? liveStroke;

  /// Which layer [liveStroke] belongs to. Ignored when there is no live stroke.
  final String? liveLayerId;

  @override
  void paint(Canvas canvas, Size size) {
    if (scale <= 0) return;

    canvas.save();
    canvas.scale(scale);

    for (final layer in document.layers) {
      final live = layer.id == liveLayerId ? liveStroke : null;
      if (!layer.visible || layer.opacity == 0) continue;
      if (layer.elements.isEmpty && live == null) continue;
      _paintLayer(canvas, layer, live);
    }

    canvas.restore();
  }

  void _paintLayer(Canvas canvas, Layer layer, Stroke? live) {
    // Always an offscreen layer, not only when translucent: BlendMode.clear
    // needs somewhere bounded to erase, and compositing the layer as a whole
    // stops its overlapping strokes showing through each other.
    canvas.saveLayer(
      null,
      Paint()..color = Color.fromARGB((layer.opacity * 255).round(), 0, 0, 0),
    );

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

    if (live != null) _paintStroke(canvas, live);

    canvas.restore();
  }

  void _paintStroke(Canvas canvas, Stroke stroke) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    if (stroke.isEraser) {
      // Clears within this layer's offscreen buffer only. The colour is
      // irrelevant; clear ignores it.
      paint.blendMode = BlendMode.clear;
    } else {
      paint.color = colorFromRGBA(stroke.colorRGBA);
    }

    canvas.drawPath(
      buildVariableWidthPath(stroke.points, stroke.baseWidth),
      paint,
    );
  }

  @override
  bool shouldRepaint(DocumentPainter old) =>
      // Documents and strokes are immutable, so a change means a new instance.
      !identical(old.document, document) ||
      !identical(old.liveStroke, liveStroke) ||
      old.liveLayerId != liveLayerId ||
      old.scale != scale;
}
