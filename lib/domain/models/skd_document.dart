import 'package:inkpad/domain/models/bounds.dart';
import 'package:inkpad/domain/models/canvas_element.dart';
import 'package:inkpad/domain/models/layer.dart';
import 'package:uuid/uuid.dart';

/// Where an element lives: the [layer] holding it, and the [element] itself.
typedef ElementLocation = ({Layer layer, CanvasElement element});

/// A whole document: a fixed-size canvas and a bottom-to-top stack of layers.
///
/// Immutable. Never mutate one from UI code — go through a command object so
/// the change can be undone.
class SkdDocument {
  SkdDocument({
    required this.canvasWidth,
    required this.canvasHeight,
    required List<Layer> layers,
    this.backgroundRGBA = 0xFFFFFFFF,
  }) : assert(canvasWidth > 0, 'canvasWidth must be positive'),
       assert(canvasHeight > 0, 'canvasHeight must be positive'),
       assert(layers.isNotEmpty, 'a document always has at least one layer'),
       assert(
         layers.map((l) => l.id).toSet().length == layers.length,
         'layer ids must be unique',
       ),
       layers = List.unmodifiable(layers);

  /// A blank document with a single empty layer.
  ///
  /// [layerId] is generated when omitted; pass one to keep a test deterministic.
  factory SkdDocument.newDefault({
    int canvasWidth = 1920,
    int canvasHeight = 1080,
    int backgroundRGBA = 0xFFFFFFFF,
    String? layerId,
    String layerName = 'Layer 1',
  }) => SkdDocument(
    canvasWidth: canvasWidth,
    canvasHeight: canvasHeight,
    backgroundRGBA: backgroundRGBA,
    layers: [Layer(id: layerId ?? const Uuid().v4(), name: layerName)],
  );

  /// Document-space size, in logical pixels at 100% zoom.
  final int canvasWidth;
  final int canvasHeight;

  /// Packed 0xRRGGBBAA. `document.json` stores this as `#RRGGBB`; the alpha
  /// byte survives only in memory, where PNG export uses it to decide whether
  /// to fill the background at all.
  final int backgroundRGBA;

  /// Bottom to top: `layers.last` paints over the rest. Never empty.
  /// Unmodifiable.
  final List<Layer> layers;

  int get layerCount => layers.length;

  /// Total elements across every layer, visible or not.
  int get elementCount =>
      layers.fold(0, (sum, layer) => sum + layer.elementCount);

  /// True when no layer holds anything. A blank document is still valid.
  bool get isEmpty => layers.every((layer) => layer.isEmpty);

  /// Index of [id] in [layers], or `-1` when absent.
  int indexOfLayer(String id) => layers.indexWhere((layer) => layer.id == id);

  /// The layer with [id], or `null` when absent.
  Layer? layerById(String id) {
    final index = indexOfLayer(id);
    return index == -1 ? null : layers[index];
  }

  /// The element with [id] and the layer holding it, or `null` when no layer
  /// holds it.
  ///
  /// Element ids are unique across the document, so the first match wins.
  /// Searches top layer first, matching what a click would hit.
  ElementLocation? findElement(String id) {
    for (final layer in layers.reversed) {
      final element = layer.elementById(id);
      if (element != null) return (layer: layer, element: element);
    }
    return null;
  }

  /// The box around every element in every layer, or `null` when the document
  /// holds nothing with bounds. Ignores layer visibility and the canvas edges,
  /// so it may extend beyond the page.
  Bounds? get bounds {
    Bounds? result;
    for (final layer in layers) {
      final layerBounds = layer.bounds;
      if (layerBounds == null) continue;
      result = result == null ? layerBounds : result.union(layerBounds);
    }
    return result;
  }

  /// A copy with the layer sharing [layer]'s id replaced, keeping its position
  /// in the stack.
  ///
  /// Throws [ArgumentError] when no layer carries that id — a command that
  /// silently no-ops would report an undo it never performed.
  SkdDocument replaceLayer(Layer layer) {
    final index = indexOfLayer(layer.id);
    if (index == -1) {
      throw ArgumentError.value(layer.id, 'layer.id', 'no such layer');
    }
    final next = [...layers];
    next[index] = layer;
    return copyWith(layers: next);
  }

  /// A copy with [layer] inserted at [index], counting from the bottom.
  ///
  /// [index] may equal [layerCount], which puts the layer on top.
  SkdDocument insertLayer(int index, Layer layer) {
    if (index < 0 || index > layers.length) {
      throw RangeError.range(index, 0, layers.length, 'index');
    }
    if (indexOfLayer(layer.id) != -1) {
      throw ArgumentError.value(layer.id, 'layer.id', 'duplicate layer id');
    }
    return copyWith(layers: [...layers]..insert(index, layer));
  }

  /// A copy without the layer with [id].
  ///
  /// Throws [StateError] when it is the only layer: a document always has one.
  /// Throws [ArgumentError] when no such layer exists.
  SkdDocument removeLayer(String id) {
    final index = indexOfLayer(id);
    if (index == -1) {
      throw ArgumentError.value(id, 'id', 'no such layer');
    }
    if (layers.length == 1) {
      throw StateError('cannot remove the only layer of a document');
    }
    return copyWith(layers: [...layers]..removeAt(index));
  }

  /// A copy with the layer at [oldIndex] moved so it ends up at [newIndex] in
  /// the returned list. Both indices address the *resulting* list, as with
  /// `Layer.moveElement`.
  SkdDocument moveLayer(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= layers.length) {
      throw RangeError.range(oldIndex, 0, layers.length - 1, 'oldIndex');
    }
    if (newIndex < 0 || newIndex >= layers.length) {
      throw RangeError.range(newIndex, 0, layers.length - 1, 'newIndex');
    }
    if (oldIndex == newIndex) return this;

    final next = [...layers];
    next.insert(newIndex, next.removeAt(oldIndex));
    return copyWith(layers: next);
  }

  SkdDocument copyWith({
    int? canvasWidth,
    int? canvasHeight,
    int? backgroundRGBA,
    List<Layer>? layers,
  }) => SkdDocument(
    canvasWidth: canvasWidth ?? this.canvasWidth,
    canvasHeight: canvasHeight ?? this.canvasHeight,
    backgroundRGBA: backgroundRGBA ?? this.backgroundRGBA,
    layers: layers ?? this.layers,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkdDocument &&
          canvasWidth == other.canvasWidth &&
          canvasHeight == other.canvasHeight &&
          backgroundRGBA == other.backgroundRGBA &&
          _layersEqual(layers, other.layers);

  @override
  int get hashCode => Object.hash(
    canvasWidth,
    canvasHeight,
    backgroundRGBA,
    Object.hashAll(layers),
  );

  @override
  String toString() =>
      'SkdDocument(${canvasWidth}x$canvasHeight, layers: ${layers.length}, '
      'elements: $elementCount)';
}

bool _layersEqual(List<Layer> a, List<Layer> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
