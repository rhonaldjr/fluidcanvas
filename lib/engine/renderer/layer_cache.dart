import 'dart:ui' as ui;

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

/// Draws one stroke in document space.
///
/// An eraser clears instead of painting. It only reaches whatever offscreen
/// buffer it is drawn into — a layer's cached image, or a `saveLayer` — which
/// is what stops it punching through the layers beneath.
void paintStroke(Canvas canvas, Stroke stroke) {
  if (stroke.points.isEmpty) return;

  final paint = Paint()
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  if (stroke.isEraser) {
    paint.blendMode = BlendMode.clear;
  } else {
    paint.color = colorFromRGBA(stroke.colorRGBA);
  }

  canvas.drawPath(
    buildVariableWidthPath(stroke.points, stroke.baseWidth),
    paint,
  );
}

/// Draws one element. Shapes are skipped until task 8.2.
void _paintElement(Canvas canvas, CanvasElement element) {
  switch (element) {
    case Stroke():
      paintStroke(canvas, element);
    case Shape():
      // Deliberately not a `default` case: the sealed type must keep failing to
      // compile when a variant is added.
      break;
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
ui.Image renderElementsToImage(
  List<CanvasElement> elements,
  int width,
  int height, {
  ui.Image? over,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  if (over != null) canvas.drawImage(over, Offset.zero, Paint());
  for (final element in elements) {
    _paintElement(canvas, element);
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
        ? renderElementsToImage(appended, width, height, over: entry!.image)
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
