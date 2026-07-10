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
    this.liveShape,
    this.liveConnector,
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

  /// The shape being dragged out, painted into the same layer.
  final Shape? liveShape;

  /// The connector being dragged out. It resolves its bound ends against the
  /// active layer's committed elements, exactly as it will once committed.
  final Connector? liveConnector;

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
      final isActive = identical(layer, layers.last);
      final stroke = isActive ? liveStroke : null;
      final shape = isActive ? liveShape : null;
      final connector = isActive ? liveConnector : null;
      if (!layer.visible || layer.opacity == 0) continue;
      if (layer.elements.isEmpty &&
          stroke == null &&
          shape == null &&
          connector == null) {
        continue;
      }
      _paintLayer(canvas, layer, stroke, shape, connector);
    }

    canvas.restore();
  }

  void _paintLayer(
    Canvas canvas,
    Layer layer,
    Stroke? live,
    Shape? shape,
    Connector? connector,
  ) {
    // Opacity is applied here, not baked into the cached image.
    final composite = Paint()
      ..color = Color.fromARGB((layer.opacity * 255).round(), 0, 0, 0)
      ..filterQuality = FilterQuality.medium;

    // Text glyphs do not survive `Picture.toImageSync`, which the layer cache
    // uses — paths (strokes, shapes) rasterize fine, but `drawParagraph` comes
    // out blank on the real renderer (the offscreen path used by `flutter test`
    // is the exception, which is why unit tests never caught this). So a layer
    // holding any text is painted **live**, in z-order, exactly like the export
    // path does. Layers without text keep the fast cached image.
    final hasText = layerHasText(layer);
    final hasLive = live != null || shape != null || connector != null;

    if (hasText) {
      canvas.saveLayer(null, composite);
      for (final element in layer.elements) {
        paintElement(canvas, element, siblings: layer.elements);
      }
      if (live != null) paintStroke(canvas, live);
      if (shape != null) paintShape(canvas, shape);
      if (connector != null) paintConnector(canvas, connector, layer.elements);
      canvas.restore();
      return;
    }

    if (!hasLive) {
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
    if (live != null) paintStroke(canvas, live);
    if (shape != null) paintShape(canvas, shape);
    if (connector != null) paintConnector(canvas, connector, layer.elements);
    canvas.restore();
  }

  @override
  bool shouldRepaint(LayerStackPainter old) =>
      // Layers and strokes are immutable, so a change means a new instance.
      !identical(old.liveStroke, liveStroke) ||
      !identical(old.liveShape, liveShape) ||
      !identical(old.liveConnector, liveConnector) ||
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
