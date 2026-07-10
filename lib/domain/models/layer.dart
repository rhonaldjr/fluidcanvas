import 'package:inkpad/domain/models/bounds.dart';
import 'package:inkpad/domain/models/canvas_element.dart';

/// How a layer composites onto the layers beneath it.
///
/// [wireName] is the string stored in `document.json`. The renderer maps these
/// onto Flutter's `BlendMode`; `domain/` stays free of Flutter imports.
enum LayerBlendMode {
  normal('normal'),
  multiply('multiply'),
  screen('screen'),
  overlay('overlay'),
  darken('darken'),
  lighten('lighten');

  const LayerBlendMode(this.wireName);

  final String wireName;

  /// Falls back to [normal] for anything unrecognized.
  ///
  /// The format spec requires this: a document written by a future version
  /// using a blend mode we don't know must still open, compositing normally,
  /// rather than failing to load. Contrast with `ShapeType.fromValue`, which
  /// throws — an unknown shape has no safe default, an unknown blend mode does.
  static LayerBlendMode fromWireName(String name) => values.firstWhere(
    (mode) => mode.wireName == name,
    orElse: () => LayerBlendMode.normal,
  );
}

/// One layer of a document: an ordered stack of elements plus its compositing
/// settings.
///
/// [elements] runs **bottom to top** — the last element paints last, on top of
/// the others. Layers are immutable; every mutator returns a copy.
class Layer {
  Layer({
    required this.id,
    required this.name,
    this.visible = true,
    this.opacity = 1.0,
    this.blendMode = LayerBlendMode.normal,
    List<CanvasElement> elements = const [],
  }) : assert(opacity >= 0.0 && opacity <= 1.0, 'opacity must be in 0..1'),
       elements = List.unmodifiable(elements);

  final String id;
  final String name;
  final bool visible;

  /// 0..1.
  final double opacity;

  final LayerBlendMode blendMode;

  /// Bottom to top. Unmodifiable.
  final List<CanvasElement> elements;

  bool get isEmpty => elements.isEmpty;
  int get elementCount => elements.length;

  /// Whether this layer contributes any pixels: hidden and fully transparent
  /// layers are skipped by the renderer and by hit-testing.
  bool get contributesPixels => visible && opacity > 0 && elements.isNotEmpty;

  /// Index of [id] in [elements], or `-1` when absent.
  int indexOfElement(String id) => elements.indexWhere((e) => e.id == id);

  /// The element with [id], or `null` when absent.
  CanvasElement? elementById(String id) {
    final index = indexOfElement(id);
    return index == -1 ? null : elements[index];
  }

  /// The box around every element, or `null` when the layer holds nothing with
  /// bounds. Ignores [visible] and stroke widths.
  Bounds? get bounds {
    Bounds? result;
    for (final element in elements) {
      final elementBounds = element.bounds;
      if (elementBounds == null) continue;
      result = result == null ? elementBounds : result.union(elementBounds);
    }
    return result;
  }

  /// A copy with [element] on top of the stack.
  Layer addElement(CanvasElement element) =>
      copyWith(elements: [...elements, element]);

  /// A copy with [element] inserted at [index], pushing later elements up.
  ///
  /// [index] may equal [elementCount], which appends.
  Layer insertElement(int index, CanvasElement element) {
    if (index < 0 || index > elements.length) {
      throw RangeError.range(index, 0, elements.length, 'index');
    }
    return copyWith(elements: [...elements]..insert(index, element));
  }

  /// A copy without the element with [id].
  ///
  /// Throws [ArgumentError] when no such element exists. Silently succeeding
  /// would let a buggy command report an undo it never performed.
  Layer removeElement(String id) {
    final index = indexOfElement(id);
    if (index == -1) {
      throw ArgumentError.value(
        id,
        'id',
        'no such element in layer ${this.id}',
      );
    }
    return copyWith(elements: [...elements]..removeAt(index));
  }

  /// A copy with the element sharing [element]'s id replaced, keeping its
  /// position in the stack.
  ///
  /// Throws [ArgumentError] when no element has that id.
  Layer replaceElement(CanvasElement element) {
    final index = indexOfElement(element.id);
    if (index == -1) {
      throw ArgumentError.value(
        element.id,
        'element.id',
        'no such element in layer $id',
      );
    }
    final next = [...elements];
    next[index] = element;
    return copyWith(elements: next);
  }

  /// A copy with the element at [oldIndex] moved so that it ends up at
  /// [newIndex] in the returned list.
  ///
  /// Both indices address the *resulting* list, which is what makes
  /// `moveElement(0, 2)` on `[a, b, c]` give `[b, c, a]` rather than
  /// `[b, a, c]`. `ReorderableListView` reports an index computed before the
  /// removal, so callers from the UI must decrement it when moving downward.
  Layer moveElement(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= elements.length) {
      throw RangeError.range(oldIndex, 0, elements.length - 1, 'oldIndex');
    }
    if (newIndex < 0 || newIndex >= elements.length) {
      throw RangeError.range(newIndex, 0, elements.length - 1, 'newIndex');
    }
    if (oldIndex == newIndex) return this;

    final next = [...elements];
    next.insert(newIndex, next.removeAt(oldIndex));
    return copyWith(elements: next);
  }

  Layer copyWith({
    String? id,
    String? name,
    bool? visible,
    double? opacity,
    LayerBlendMode? blendMode,
    List<CanvasElement>? elements,
  }) => Layer(
    id: id ?? this.id,
    name: name ?? this.name,
    visible: visible ?? this.visible,
    opacity: opacity ?? this.opacity,
    blendMode: blendMode ?? this.blendMode,
    elements: elements ?? this.elements,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Layer &&
          id == other.id &&
          name == other.name &&
          visible == other.visible &&
          opacity == other.opacity &&
          blendMode == other.blendMode &&
          _elementsEqual(elements, other.elements);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    visible,
    opacity,
    blendMode,
    Object.hashAll(elements),
  );

  @override
  String toString() =>
      'Layer($id, "$name", visible: $visible, opacity: $opacity, '
      'elements: ${elements.length})';
}

bool _elementsEqual(List<CanvasElement> a, List<CanvasElement> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
