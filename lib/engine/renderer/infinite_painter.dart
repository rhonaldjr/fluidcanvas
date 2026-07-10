import 'package:flutter/material.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/renderer/layer_cache.dart';

/// Paints every layer of an **infinite** document directly, without the layer
/// cache.
///
/// The cache rasterises each layer to a fixed `width × height` image, which
/// cannot hold content that may sit anywhere on an unbounded plane — including
/// negative coordinates. So an infinite canvas repaints its elements live each
/// frame, translated and scaled by the view transform. That is slower than the
/// cached bounded path, and the trade the infinite mode makes.
class InfiniteCanvasPainter extends CustomPainter {
  const InfiniteCanvasPainter({
    required this.layers,
    required this.activeLayerId,
    required this.scale,
    required this.origin,
    this.liveStroke,
    this.liveShape,
    this.liveConnector,
  });

  final List<Layer> layers;
  final String activeLayerId;

  /// Document-to-screen scale (the zoom).
  final double scale;

  /// Where document (0, 0) sits on screen, in this painter's box.
  final Offset origin;

  /// The in-progress stroke, shape and connector, drawn into the active layer.
  final Stroke? liveStroke;
  final Shape? liveShape;
  final Connector? liveConnector;

  @override
  void paint(Canvas canvas, Size size) {
    if (scale <= 0) return;
    canvas
      ..save()
      ..translate(origin.dx, origin.dy)
      ..scale(scale);

    for (final layer in layers) {
      final isActive = layer.id == activeLayerId;
      final live = isActive ? liveStroke : null;
      final shape = isActive ? liveShape : null;
      final connector = isActive ? liveConnector : null;
      final hasLive = live != null || shape != null || connector != null;

      if (!layer.visible || layer.opacity == 0) continue;
      if (layer.elements.isEmpty && !hasLive) continue;

      // A layer composites as a unit: its opacity applies to the whole of it,
      // and an eraser inside it clears only its own pixels. Blend modes are not
      // applied here — the bounded renderer does not apply them either, so the
      // two stay consistent until that gap is closed.
      canvas.saveLayer(
        null,
        Paint()..color = Color.fromARGB((layer.opacity * 255).round(), 0, 0, 0),
      );
      for (final element in layer.elements) {
        paintElement(canvas, element, siblings: layer.elements);
      }
      if (live != null) paintStroke(canvas, live);
      if (shape != null) paintShape(canvas, shape);
      if (connector != null) {
        paintConnector(canvas, connector, layer.elements);
      }
      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(InfiniteCanvasPainter old) =>
      old.scale != scale ||
      old.origin != origin ||
      !identical(old.layers, layers) ||
      old.activeLayerId != activeLayerId ||
      !identical(old.liveStroke, liveStroke) ||
      !identical(old.liveShape, liveShape) ||
      !identical(old.liveConnector, liveConnector);
}
