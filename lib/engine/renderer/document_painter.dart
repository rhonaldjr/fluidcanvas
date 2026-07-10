import 'package:flutter/material.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/renderer/layer_cache.dart';

export 'package:inkpad/engine/renderer/layer_cache.dart'
    show colorFromRGBA, paintShape, paintStroke, paintText;

/// Paints a whole document straight from its elements, with no layer cache.
///
/// Used where a document is drawn once — PNG export (12.1), thumbnails (9.6),
/// tests. The interactive canvas uses [LayerStackPainter] over a [LayerCache]
/// instead, so that drawing does not re-rasterize every committed stroke.
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
      paintElement(canvas, element, siblings: layer.elements);
    }

    if (live != null) paintStroke(canvas, live);

    canvas.restore();
  }

  @override
  bool shouldRepaint(DocumentPainter old) =>
      // Documents and strokes are immutable, so a change means a new instance.
      !identical(old.document, document) ||
      !identical(old.liveStroke, liveStroke) ||
      old.liveLayerId != liveLayerId ||
      old.scale != scale;
}
