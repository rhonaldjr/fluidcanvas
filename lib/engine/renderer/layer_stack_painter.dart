import 'package:flutter/material.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/renderer/layer_cache.dart';

/// Paints a contiguous slice of a document's layers from their cached images.
///
/// The canvas is split into three of these — below the active layer, the active
/// layer, and above it — each in its own `RepaintBoundary`. Only the active
/// slice carries [liveStroke], so only it repaints while drawing. That is what
/// task 5.2 buys: a pointer event costs one image blit plus one path, not a
/// re-rasterization of every stroke in the document.
class LayerStackPainter extends CustomPainter {
  const LayerStackPainter({
    required this.layers,
    required this.documentWidth,
    required this.documentHeight,
    required this.scale,
    required this.cache,
    this.liveStroke,
    this.debugLabel,
  });

  /// The slice to paint, bottom first.
  final List<Layer> layers;

  final int documentWidth;
  final int documentHeight;

  /// Page screen size divided by document size.
  final double scale;

  final LayerCache cache;

  /// The stroke under the pointer. Painted into the *last* layer of [layers],
  /// which callers arrange to be the active one.
  final Stroke? liveStroke;

  /// Counted by [paintCounts] in debug builds, so tests can assert which
  /// boundaries actually repaint.
  final String? debugLabel;

  /// How many times each labelled painter has painted. Debug builds only.
  static final Map<String, int> paintCounts = {};

  static void resetPaintCounts() => paintCounts.clear();

  @override
  void paint(Canvas canvas, Size size) {
    assert(() {
      if (debugLabel != null) {
        paintCounts.update(debugLabel!, (n) => n + 1, ifAbsent: () => 1);
      }
      return true;
    }());

    if (scale <= 0 || layers.isEmpty) return;

    canvas.save();
    canvas.scale(scale);

    for (final layer in layers) {
      final live = identical(layer, layers.last) ? liveStroke : null;
      if (!layer.visible || layer.opacity == 0) continue;
      if (layer.elements.isEmpty && live == null) continue;
      _paintLayer(canvas, layer, live);
    }

    canvas.restore();
  }

  void _paintLayer(Canvas canvas, Layer layer, Stroke? live) {
    // Opacity is applied here, not baked into the cached image.
    final composite = Paint()
      ..color = Color.fromARGB((layer.opacity * 255).round(), 0, 0, 0)
      ..filterQuality = FilterQuality.medium;

    if (live == null) {
      if (layer.elements.isEmpty) return;
      canvas.drawImage(
        cache.imageFor(layer, width: documentWidth, height: documentHeight),
        Offset.zero,
        composite,
      );
      return;
    }

    // The live stroke must composite *inside* this layer: an eraser has to
    // clear the layer's own pixels and nothing beneath them.
    canvas.saveLayer(null, composite);
    if (layer.elements.isNotEmpty) {
      canvas.drawImage(
        cache.imageFor(layer, width: documentWidth, height: documentHeight),
        Offset.zero,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    paintStroke(canvas, live);
    canvas.restore();
  }

  @override
  bool shouldRepaint(LayerStackPainter old) =>
      // Layers and strokes are immutable, so a change means a new instance.
      !identical(old.liveStroke, liveStroke) ||
      old.scale != scale ||
      old.documentWidth != documentWidth ||
      old.documentHeight != documentHeight ||
      !identical(old.cache, cache) ||
      !_sameLayers(old.layers, layers);

  static bool _sameLayers(List<Layer> a, List<Layer> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }
}
