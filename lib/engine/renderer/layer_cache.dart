import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/renderer/brushes.dart';
import 'package:inkpad/engine/rough.dart';
import 'package:inkpad/engine/shape_paths.dart';
import 'package:inkpad/engine/text_layout.dart';
import 'package:inkpad/engine/text_on_path.dart';
import 'package:inkpad/engine/renderer/variable_width.dart';

/// Unpacks a 0xRRGGBBAA int, as stored on the models and in `.skd`, into a
/// Flutter [Color], which is ARGB.
Color colorFromRGBA(int rgba) => Color.fromARGB(
  rgba & 0xFF,
  (rgba >> 24) & 0xFF,
  (rgba >> 16) & 0xFF,
  (rgba >> 8) & 0xFF,
);

/// Draws one stroke in document space.
///
/// An eraser clears instead of painting. It only reaches whatever offscreen
/// buffer it is drawn into — a layer's cached image, or a `saveLayer` — which
/// is what stops it punching through the layers beneath.
void paintStroke(Canvas canvas, Stroke stroke) {
  if (stroke.points.isEmpty) return;

  switch (stroke.toolId) {
    case ToolId.eraser:
      canvas.drawPath(
        buildVariableWidthPath(stroke.points, stroke.baseWidth),
        Paint()
          ..style = PaintingStyle.fill
          ..isAntiAlias = true
          ..blendMode = BlendMode.clear,
      );
    case ToolId.pencil:
      _paintPencil(canvas, stroke);
    case ToolId.airbrush:
      _paintAirbrush(canvas, stroke);
    case ToolId.texture:
      _paintTexture(canvas, stroke);
    default:
      // Pen, and any brush a newer file used that this build cannot render.
      canvas.drawPath(
        buildVariableWidthPath(stroke.points, stroke.baseWidth),
        Paint()
          ..style = PaintingStyle.fill
          ..isAntiAlias = true
          ..color = colorFromRGBA(stroke.colorRGBA),
      );
  }
}

/// [rgba] with its alpha multiplied by [factor].
Color _withAlpha(int rgba, double factor) {
  final base = colorFromRGBA(rgba);
  return base.withValues(alpha: base.a * factor);
}

/// A solid but slightly translucent fill, speckled with graphite grain.
void _paintPencil(Canvas canvas, Stroke stroke) {
  canvas
    ..drawPath(
      buildVariableWidthPath(stroke.points, stroke.baseWidth),
      Paint()
        ..style = PaintingStyle.fill
        ..isAntiAlias = true
        ..color = _withAlpha(stroke.colorRGBA, 0.82),
    )
    ..drawPath(
      buildPencilGrain(stroke),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true
        ..color = _withAlpha(stroke.colorRGBA, 0.5),
    );
}

/// A soft, low-opacity spray that builds up where it overlaps itself.
void _paintAirbrush(Canvas canvas, Stroke stroke) {
  canvas.drawPath(
    buildVariableWidthPath(stroke.points, stroke.baseWidth),
    Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..color = _withAlpha(stroke.colorRGBA, 0.35)
      ..maskFilter = MaskFilter.blur(
        BlurStyle.normal,
        math.max(1.0, stroke.baseWidth * 0.5),
      ),
  );
}

/// Broken dabs stamped along the centreline, for a dry, textured mark.
void _paintTexture(Canvas canvas, Stroke stroke) {
  canvas.drawPath(
    buildTextureStamps(stroke),
    Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..color = _withAlpha(stroke.colorRGBA, 0.78),
  );
}

/// Draws one shape in document space, rotated about its own centre.
void paintShape(Canvas canvas, Shape shape) {
  final box = shape.normalized();
  if (box.w == 0 && box.h == 0) return;

  final rect = Rect.fromLTWH(box.x, box.y, box.w, box.h);
  // The precise outline: what gets filled, and what gets stroked unless the
  // shape asked for the hand-drawn look.
  final path = buildShapePath(box.type, rect, strokeWidth: box.strokeWidth);
  final outline = box.isRough
      ? buildRoughPath(
          box.type,
          rect,
          seed: box.seed,
          strokeWidth: box.strokeWidth,
        )
      : path;

  canvas.save();
  if (box.isRotated) {
    canvas
      ..translate(box.centerX, box.centerY)
      ..rotate(box.rotation)
      ..translate(-box.centerX, -box.centerY);
  }

  // A line and an arrow enclose no area, so a fill colour on one is ignored.
  // The fill always follows the precise outline: a rough one is a handful of
  // open subpaths, one per edge, and filling that paints nonsense.
  if (box.isFilled && shapeTypeIsClosed(box.type)) {
    canvas.drawPath(
      path,
      Paint()
        ..color = colorFromRGBA(box.fillColorRGBA)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  final pattern = dashPatternFor(box.strokeStyle);
  canvas.drawPath(
    pattern == null ? outline : dashPath(outline, pattern, box.strokeWidth),
    Paint()
      ..color = colorFromRGBA(box.strokeColorRGBA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = box.strokeWidth
      ..strokeCap = box.strokeStyle == StrokeStyle.dotted
          ? StrokeCap.round
          : StrokeCap.butt
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true,
  );

  canvas.restore();
}

/// Draws one text element, rotated about its own centre and shrunk to fit.
///
/// [siblings] is only needed when the text flows along a path — then its glyphs
/// follow the bound element's outline instead of wrapping in its own box.
void paintText(
  Canvas canvas,
  TextElement element, {
  List<CanvasElement> siblings = const [],
}) {
  if (element.isEmpty) return;

  if (element.isOnPath) {
    final id = element.pathElementId;
    final target = siblings.where((e) => e.id == id).firstOrNull;
    final path = target == null ? null : outlinePathFor(target, siblings);
    if (path != null) {
      paintTextOnPath(canvas, element, path);
      return;
    }
    // The path is gone; fall through and draw the text in its own box, so it
    // does not simply vanish.
  }

  final layout = layoutText(element);

  canvas.save();
  if (element.isRotated) {
    canvas
      ..translate(element.centerX, element.centerY)
      ..rotate(element.rotation)
      ..translate(-element.centerX, -element.centerY);
  }
  // Never spill outside the box: at the fit floor the text genuinely overflows.
  canvas
    ..clipRect(Rect.fromLTWH(element.x, element.y, element.w, element.h))
    ..drawParagraph(layout.paragraph, Offset(element.x, element.y));

  if (layout.overflows) {
    // A marker rather than silence: the text is smaller than the floor allows.
    canvas.drawCircle(
      Offset(element.x + element.w - 4, element.y + element.h - 4),
      3,
      Paint()..color = const Color(0xFFE53935),
    );
  }
  canvas.restore();
}

/// Whether [layer] holds any text — directly or inside a group.
///
/// Text glyphs do not survive `Picture.toImageSync`, which the layer cache
/// uses, so a layer that answers true must be painted live rather than served
/// from the cache. See [LayerStackPainter].
bool layerHasText(Layer layer) => layer.elements.any(elementHasText);

/// Whether [element] is, or contains, a text element.
bool elementHasText(CanvasElement element) => switch (element) {
  TextElement() => true,
  Group() => element.leaves.any((e) => e is TextElement),
  Stroke() || Shape() || Connector() => false,
};

/// Whether a text-holding layer must composite through its own offscreen
/// buffer — a sub-1 opacity, or an eraser (committed or [live]) that has to
/// clear only its own pixels.
///
/// It matters because text glyphs do not render inside a `saveLayer` on the
/// real renderer, so a text layer that answers **false** here is drawn straight
/// onto the canvas (text visible), and one that answers true draws its text on
/// top of the isolated content instead.
bool textLayerNeedsIsolation(Layer layer, {Stroke? live}) {
  final erasing =
      layer.elements.any((e) => e is Stroke && e.isEraser) ||
      (live != null && live.isEraser);
  return layer.opacity < 1.0 || erasing;
}

/// Draws one element.
///
/// [siblings] is the list [element] lives in. Only a [Connector] needs it: its
/// bound ends are derived from the elements they point at, never stored.
void paintElement(
  Canvas canvas,
  CanvasElement element, {
  List<CanvasElement> siblings = const [],
}) {
  switch (element) {
    case Stroke():
      paintStroke(canvas, element);
    case Shape():
      paintShape(canvas, element);
    case TextElement():
      paintText(canvas, element, siblings: siblings);
    case Connector():
      paintConnector(canvas, element, siblings);
    case Group():
      // A group has nothing of its own to draw. Its children resolve their
      // bindings against each other, not against the layer around them.
      for (final child in element.children) {
        paintElement(canvas, child, siblings: element.children);
      }
  }
}

/// Draws a connector as the line between its resolved endpoints.
void paintConnector(
  Canvas canvas,
  Connector connector,
  List<CanvasElement> siblings,
) {
  final line = resolveConnector(connector, siblings);
  final start = Offset(line.x1, line.y1);
  final end = Offset(line.x2, line.y2);
  if ((end - start).distance < 1e-6) return;

  final path = Path()
    ..moveTo(start.dx, start.dy)
    ..lineTo(end.dx, end.dy);

  final paint = Paint()
    ..color = colorFromRGBA(connector.strokeColorRGBA)
    ..style = PaintingStyle.stroke
    ..strokeWidth = connector.strokeWidth
    ..strokeCap = connector.strokeStyle == StrokeStyle.dotted
        ? StrokeCap.round
        : StrokeCap.butt
    ..isAntiAlias = true;

  final pattern = dashPatternFor(connector.strokeStyle);
  canvas.drawPath(
    pattern == null ? path : dashPath(path, pattern, connector.strokeWidth),
    paint,
  );

  // The heads reuse the arrow shape's geometry, built from the two points so
  // they point the way the line actually runs.
  if (connector.endArrow) {
    canvas.drawPath(
      arrowHeadAt(start, end, connector.strokeWidth),
      paint..strokeCap = StrokeCap.butt,
    );
  }
  if (connector.startArrow) {
    canvas.drawPath(arrowHeadAt(end, start, connector.strokeWidth), paint);
  }
}

/// Rasterizes a layer's committed elements into an image, at document
/// resolution.
///
/// The image *is* the layer's buffer, so an eraser stroke clears against
/// transparency inside it with no extra `saveLayer` needed. Layer opacity is
/// deliberately not baked in: it is applied when the image is composited, so
/// dragging an opacity slider never invalidates the cache.
///
/// Pass [over] to build on an already-rendered image and paint only [elements]
/// on top of it — see [LayerCache.imageFor].
///
/// [siblings] defaults to [elements], and must be given whenever [elements] is
/// only a *slice* of its layer: a connector in the appended tail may bind to a
/// shape further down, and it resolves its ends against the whole list.
ui.Image renderElementsToImage(
  List<CanvasElement> elements,
  int width,
  int height, {
  ui.Image? over,
  List<CanvasElement>? siblings,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  if (over != null) canvas.drawImage(over, Offset.zero, Paint());
  for (final element in elements) {
    paintElement(canvas, element, siblings: siblings ?? elements);
  }

  final picture = recorder.endRecording();
  // Synchronous: the widget builds the cache during layout, and an async
  // rasterization would show a blank layer for a frame after every commit.
  final image = picture.toImageSync(width, height);
  picture.dispose();
  return image;
}

/// Rasterizes a whole layer from scratch.
ui.Image renderLayerToImage(Layer layer, int width, int height) =>
    renderElementsToImage(layer.elements, width, height);

class _CachedLayer {
  _CachedLayer(this.elements, this.image, this.width, this.height);

  final List<CanvasElement> elements;
  final ui.Image image;
  final int width;
  final int height;
}

/// Keeps one rasterized image per layer, rebuilt only when that layer's
/// elements change.
///
/// Invalidation keys on the **identity** of `layer.elements`. `Layer` is
/// immutable and hands back the same list from `copyWith` when the elements are
/// untouched, so renaming a layer or changing its opacity is a cache hit.
///
/// Owned by the widget that paints, and disposed with it: every image holds GPU
/// memory (a 1920x1080 layer is about 8 MB).
class LayerCache {
  final Map<String, _CachedLayer> _entries = {};

  /// How many layers are currently rasterized.
  int get length => _entries.length;

  /// Whether [layer] would be served from the cache rather than re-rendered.
  bool isCached(Layer layer, {required int width, required int height}) {
    final entry = _entries[layer.id];
    return entry != null &&
        identical(entry.elements, layer.elements) &&
        entry.width == width &&
        entry.height == height;
  }

  /// The rasterized image for [layer], rendering it if the cache misses.
  ///
  /// Committing a stroke appends to the layer, leaving the earlier elements
  /// identical. That case is served by drawing the cached image and painting
  /// only the new tail on top, which keeps a commit O(new elements) instead of
  /// re-rasterizing every stroke in the layer. Anything else — an undo, a
  /// reorder, a delete — falls back to a full render.
  ui.Image imageFor(Layer layer, {required int width, required int height}) {
    final entry = _entries[layer.id];
    if (entry != null &&
        identical(entry.elements, layer.elements) &&
        entry.width == width &&
        entry.height == height) {
      return entry.image;
    }

    final appended =
        entry != null && entry.width == width && entry.height == height
        ? _appendedTail(entry.elements, layer.elements)
        : null;

    final image = appended != null
        ? renderElementsToImage(
            appended,
            width,
            height,
            over: entry!.image,
            siblings: layer.elements,
          )
        : renderElementsToImage(layer.elements, width, height);

    entry?.image.dispose();
    _entries[layer.id] = _CachedLayer(layer.elements, image, width, height);
    return image;
  }

  /// The elements appended to [before] to make [after], or `null` when [after]
  /// is not [before] plus a suffix.
  static List<CanvasElement>? _appendedTail(
    List<CanvasElement> before,
    List<CanvasElement> after,
  ) {
    if (after.length <= before.length) return null;
    for (var i = 0; i < before.length; i++) {
      // Elements are immutable, so identity is the cheap prefix test.
      if (!identical(before[i], after[i])) return null;
    }
    return after.sublist(before.length);
  }

  /// Drops images for layers no longer in the document, so deleting a layer
  /// does not leak its buffer.
  void retainOnly(Iterable<String> layerIds) {
    final keep = layerIds.toSet();
    _entries.removeWhere((id, entry) {
      if (keep.contains(id)) return false;
      entry.image.dispose();
      return true;
    });
  }

  void dispose() {
    for (final entry in _entries.values) {
      entry.image.dispose();
    }
    _entries.clear();
  }
}
