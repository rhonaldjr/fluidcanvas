import 'package:inkpad/domain/commands/command.dart';
import 'package:inkpad/domain/models/models.dart';

/// Applies [transform] to the named elements wherever they live.
///
/// Every selection command reduces to this: it captures the elements as they
/// were, so `revert` restores them verbatim rather than inverting the maths.
/// Undo is therefore exact, and a rotation of 0.1 radians undone a thousand
/// times leaves the geometry untouched.
abstract class _TransformElementsCommand extends Command {
  _TransformElementsCommand({required List<CanvasElement> before})
    : before = List.unmodifiable(before);

  /// The elements as they were, captured before the change.
  final List<CanvasElement> before;

  /// The element after the change.
  CanvasElement transform(CanvasElement element);

  @override
  SkdDocument apply(SkdDocument document) =>
      _replaceAll(document, [for (final e in before) transform(e)]);

  @override
  SkdDocument revert(SkdDocument document) => _replaceAll(document, before);
}

/// [document] with each of [elements] swapped in by id, keeping z-order.
///
/// Exposed so a drag can *preview* a transform without pushing a command per
/// frame: the widget previews, and commits one command when the pointer lifts.
SkdDocument replaceElements(
  SkdDocument document,
  List<CanvasElement> elements,
) => _replaceAll(document, elements);

SkdDocument _replaceAll(SkdDocument document, List<CanvasElement> elements) {
  var next = document;
  for (final element in elements) {
    final found = next.findElement(element.id);
    if (found == null) {
      throw ArgumentError.value(element.id, 'id', 'no such element');
    }
    next = next.replaceLayer(found.layer.replaceElement(element));
  }
  return next;
}

/// Moves elements by a fixed offset.
class MoveElementsCommand extends _TransformElementsCommand {
  MoveElementsCommand({
    required super.before,
    required this.dx,
    required this.dy,
  });

  final double dx;
  final double dy;

  @override
  String get label => 'Move';

  @override
  CanvasElement transform(CanvasElement element) => element.translated(dx, dy);
}

/// Scales elements uniformly about an anchor.
///
/// Shapes resize losslessly — the box changes, no pixels are resampled — and
/// strokes scale their point lists.
class ResizeElementsCommand extends _TransformElementsCommand {
  ResizeElementsCommand({
    required super.before,
    required this.factor,
    required this.originX,
    required this.originY,
  }) : assert(factor > 0, 'scale factor must be positive');

  final double factor;
  final double originX;
  final double originY;

  @override
  String get label => 'Resize';

  @override
  CanvasElement transform(CanvasElement element) =>
      element.scaled(factor, originX: originX, originY: originY);
}

/// Sets one element's box without touching the style inside it.
///
/// A corner drag emits [ResizeElementsCommand] and scales the font with the
/// box; a side drag emits this, so the text rewraps at the same size.
class ResizeBoxCommand extends _TransformElementsCommand {
  ResizeBoxCommand({required super.before, required this.box})
    : assert(before.length == 1, 'a box resize acts on one element');

  final Bounds box;

  @override
  String get label => 'Resize';

  @override
  CanvasElement transform(CanvasElement element) =>
      elementWithBox(element, box);
}

/// Rotates elements about a point.
class RotateElementsCommand extends _TransformElementsCommand {
  RotateElementsCommand({
    required super.before,
    required this.radians,
    required this.originX,
    required this.originY,
  });

  final double radians;
  final double originX;
  final double originY;

  @override
  String get label => 'Rotate';

  @override
  CanvasElement transform(CanvasElement element) =>
      element.rotated(radians, originX: originX, originY: originY);
}

/// Restyles shapes. Strokes in the selection are left alone.
class StyleElementsCommand extends _TransformElementsCommand {
  StyleElementsCommand({
    required super.before,
    this.strokeColorRGBA,
    this.fillColorRGBA,
    this.strokeWidth,
    this.strokeStyle,
    this.renderStyle,
  });

  final int? strokeColorRGBA;
  final int? fillColorRGBA;
  final double? strokeWidth;
  final StrokeStyle? strokeStyle;
  final ShapeRenderStyle? renderStyle;

  @override
  String get label => 'Change Style';

  @override
  CanvasElement transform(CanvasElement element) => switch (element) {
    // A shape that becomes rough needs a seed. Derived from its id rather
    // than drawn at random, or a redo would wobble differently from the apply
    // it is meant to reproduce.
    Shape() => element.copyWith(
      strokeColorRGBA: strokeColorRGBA,
      fillColorRGBA: fillColorRGBA,
      strokeWidth: strokeWidth,
      strokeStyle: strokeStyle,
      renderStyle: renderStyle,
      seed: renderStyle == ShapeRenderStyle.rough && element.seed == 0
          ? seedFromId(element.id)
          : null,
    ),
    // A connector takes the stroke colour, width and dash of the shape bar,
    // which are the only properties it shares with a shape.
    Connector() => element.copyWith(
      strokeColorRGBA: strokeColorRGBA,
      strokeWidth: strokeWidth,
      strokeStyle: strokeStyle,
    ),
    // Restyling a group restyles what is inside it.
    Group() => element.copyWith(
      children: [for (final child in element.children) transform(child)],
    ),
    // Strokes and text have their own controls; the shape style bar is not
    // theirs to change.
    Stroke() || TextElement() => element,
  };
}

/// Replaces the runs of one text element. Typing coalesces into one of these.
class EditTextCommand extends Command {
  EditTextCommand({required this.before, required List<TextRun> after})
    : after = List.unmodifiable(after);

  /// The element as it was, so undo restores it exactly.
  final TextElement before;
  final List<TextRun> after;

  @override
  String get label => 'Edit Text';

  @override
  SkdDocument apply(SkdDocument document) =>
      _replaceAll(document, [before.copyWith(runs: after)]);

  @override
  SkdDocument revert(SkdDocument document) => _replaceAll(document, [before]);
}

/// Restyles a range of a text element's runs: bold, italic, underline.
class StyleTextRunsCommand extends Command {
  StyleTextRunsCommand({
    required this.before,
    required this.start,
    required this.end,
    this.bold,
    this.italic,
    this.underline,
  });

  final TextElement before;
  final int start;
  final int end;
  final bool? bold;
  final bool? italic;
  final bool? underline;

  @override
  String get label => 'Style Text';

  @override
  SkdDocument apply(SkdDocument document) => _replaceAll(document, [
    before.copyWith(
      runs: before.runsWithStyle(
        start,
        end,
        bold: bold,
        italic: italic,
        underline: underline,
      ),
    ),
  ]);

  @override
  SkdDocument revert(SkdDocument document) => _replaceAll(document, [before]);
}

/// Changes a text element's family, size, colour, or alignment.
class StyleTextElementCommand extends Command {
  const StyleTextElementCommand({
    required this.before,
    this.fontFamily,
    this.fontSize,
    this.colorRGBA,
    this.align,
  });

  final TextElement before;
  final String? fontFamily;
  final double? fontSize;
  final int? colorRGBA;
  final TextAlignment? align;

  @override
  String get label => 'Change Text Style';

  @override
  SkdDocument apply(SkdDocument document) => _replaceAll(document, [
    before.copyWith(
      fontFamily: fontFamily,
      fontSize: fontSize,
      colorRGBA: colorRGBA,
      align: align,
    ),
  ]);

  @override
  SkdDocument revert(SkdDocument document) => _replaceAll(document, [before]);
}

/// Deletes elements, remembering where each sat so `revert` can put it back.
class DeleteElementsCommand extends Command {
  DeleteElementsCommand({
    required List<({String layerId, int index, CanvasElement element})> removed,
    List<CanvasElement> frozenBefore = const [],
    List<CanvasElement> frozenAfter = const [],
  }) : removed = List.unmodifiable(removed),
       frozenBefore = List.unmodifiable(frozenBefore),
       frozenAfter = List.unmodifiable(frozenAfter),
       assert(
         frozenBefore.length == frozenAfter.length,
         'every frozen connector needs its before and after',
       );

  /// Captured before deletion, ordered bottom-first within each layer.
  final List<({String layerId, int index, CanvasElement element})> removed;

  /// Connectors that survive but bound to something being deleted, as they
  /// were and as they become: a bound end stops following and stays where it
  /// stood. Captured rather than recomputed, so undo restores the binding
  /// exactly.
  final List<CanvasElement> frozenBefore;
  final List<CanvasElement> frozenAfter;

  @override
  String get label =>
      removed.length == 1 ? 'Delete' : 'Delete ${removed.length} Items';

  @override
  SkdDocument apply(SkdDocument document) {
    // Freeze first: the frozen positions were measured while the elements
    // being deleted were still there.
    var next = frozenAfter.isEmpty
        ? document
        : replaceElements(document, frozenAfter);
    for (final entry in removed) {
      final layer = next.layerById(entry.layerId);
      if (layer == null) {
        throw ArgumentError.value(entry.layerId, 'layerId', 'no such layer');
      }
      next = next.replaceLayer(layer.removeElement(entry.element.id));
    }
    return next;
  }

  @override
  SkdDocument revert(SkdDocument document) {
    var next = document;
    // Ascending index, so each insert lands where it was before the ones after.
    final ordered = [...removed]..sort((a, b) => a.index.compareTo(b.index));
    for (final entry in ordered) {
      final layer = next.layerById(entry.layerId);
      if (layer == null) {
        throw ArgumentError.value(entry.layerId, 'layerId', 'no such layer');
      }
      next = next.replaceLayer(layer.insertElement(entry.index, entry.element));
    }
    // The elements are back, so the connectors may bind to them again.
    return frozenBefore.isEmpty ? next : replaceElements(next, frozenBefore);
  }
}

/// Adds copies of elements to a layer, on top.
class DuplicateElementsCommand extends Command {
  DuplicateElementsCommand({
    required this.layerId,
    required List<CanvasElement> copies,
  }) : copies = List.unmodifiable(copies);

  final String layerId;

  /// The new elements, already offset and carrying fresh ids.
  final List<CanvasElement> copies;

  @override
  String get label => 'Duplicate';

  @override
  SkdDocument apply(SkdDocument document) {
    var layer = _layer(document);
    for (final copy in copies) {
      layer = layer.addElement(copy);
    }
    return document.replaceLayer(layer);
  }

  @override
  SkdDocument revert(SkdDocument document) {
    var layer = _layer(document);
    for (final copy in copies) {
      layer = layer.removeElement(copy.id);
    }
    return document.replaceLayer(layer);
  }

  Layer _layer(SkdDocument document) {
    final layer = document.layerById(layerId);
    if (layer == null) {
      throw ArgumentError.value(layerId, 'layerId', 'no such layer');
    }
    return layer;
  }
}

/// Moves one element within its layer's z-order.
class ReorderElementCommand extends Command {
  const ReorderElementCommand({
    required this.layerId,
    required this.oldIndex,
    required this.newIndex,
  });

  final String layerId;
  final int oldIndex;
  final int newIndex;

  @override
  String get label => newIndex > oldIndex ? 'Bring Forward' : 'Send Backward';

  @override
  SkdDocument apply(SkdDocument document) =>
      _move(document, oldIndex, newIndex);

  @override
  SkdDocument revert(SkdDocument document) =>
      _move(document, newIndex, oldIndex);

  SkdDocument _move(SkdDocument document, int from, int to) {
    final layer = document.layerById(layerId);
    if (layer == null) {
      throw ArgumentError.value(layerId, 'layerId', 'no such layer');
    }
    return document.replaceLayer(layer.moveElement(from, to));
  }
}
