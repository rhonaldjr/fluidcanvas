import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/engine/renderer/layer_cache.dart';

/// The rasterized image of each layer, shared by the canvas and the layer
/// panel's thumbnails.
///
/// Shared rather than owned by the canvas so a thumbnail is a blit of an image
/// that already exists, not a second rasterization of the same strokes.
final layerCacheProvider = Provider<LayerCache>((ref) {
  final cache = LayerCache();
  ref.onDispose(cache.dispose);
  return cache;
});
