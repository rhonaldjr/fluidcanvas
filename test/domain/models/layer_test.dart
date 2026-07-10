import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';

Stroke strokeAt(String id, double x, double y) => Stroke(
  id: id,
  colorRGBA: 0xFF0000FF,
  baseWidth: 2,
  points: [StrokePoint(x: x, y: y)],
);

Shape rectAt(String id, double x, double y, {double w = 10, double h = 10}) =>
    Shape(
      id: id,
      type: ShapeType.rectangle,
      x: x,
      y: y,
      w: w,
      h: h,
      strokeColorRGBA: 0xFF0000FF,
      strokeWidth: 1,
    );

Layer layerWith(List<CanvasElement> elements, {String id = 'l1'}) =>
    Layer(id: id, name: 'Layer 1', elements: elements);

List<String> idsOf(Layer layer) => [for (final e in layer.elements) e.id];

void main() {
  group('LayerBlendMode', () {
    test('wire names are pinned', () {
      expect(LayerBlendMode.normal.wireName, 'normal');
      expect(LayerBlendMode.multiply.wireName, 'multiply');
      expect(LayerBlendMode.screen.wireName, 'screen');
    });

    test('fromWireName round-trips every variant', () {
      for (final mode in LayerBlendMode.values) {
        expect(LayerBlendMode.fromWireName(mode.wireName), mode);
      }
    });

    test('an unknown blend mode falls back to normal instead of throwing', () {
      // A document from a future version must still open.
      expect(LayerBlendMode.fromWireName('color-dodge'), LayerBlendMode.normal);
      expect(LayerBlendMode.fromWireName(''), LayerBlendMode.normal);
    });
  });

  group('construction', () {
    test('defaults to visible, opaque, normal, and empty', () {
      final layer = Layer(id: 'l1', name: 'Layer 1');
      expect(layer.visible, isTrue);
      expect(layer.opacity, 1.0);
      expect(layer.blendMode, LayerBlendMode.normal);
      expect(layer.isEmpty, isTrue);
      expect(layer.elementCount, 0);
    });

    test('rejects opacity outside 0..1', () {
      expect(
        () => Layer(id: 'l', name: 'n', opacity: -0.1),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => Layer(id: 'l', name: 'n', opacity: 1.1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('elements are unmodifiable', () {
      final layer = layerWith([strokeAt('a', 0, 0)]);
      expect(
        () => layer.elements.add(strokeAt('b', 1, 1)),
        throwsUnsupportedError,
      );
    });

    test('copies the incoming list, so caller mutation cannot leak in', () {
      final source = <CanvasElement>[strokeAt('a', 0, 0)];
      final layer = layerWith(source);
      source.add(strokeAt('b', 1, 1));
      expect(layer.elementCount, 1);
    });

    test('holds strokes and shapes side by side, in one z-order', () {
      final layer = layerWith([strokeAt('s', 0, 0), rectAt('r', 0, 0)]);
      expect(idsOf(layer), ['s', 'r']);
    });
  });

  group('contributesPixels', () {
    test('true for a visible, opaque, non-empty layer', () {
      expect(layerWith([strokeAt('a', 0, 0)]).contributesPixels, isTrue);
    });

    test('false when hidden, fully transparent, or empty', () {
      final populated = layerWith([strokeAt('a', 0, 0)]);
      expect(populated.copyWith(visible: false).contributesPixels, isFalse);
      expect(populated.copyWith(opacity: 0).contributesPixels, isFalse);
      expect(layerWith(const []).contributesPixels, isFalse);
    });
  });

  group('lookup', () {
    final layer = layerWith([strokeAt('a', 0, 0), rectAt('b', 5, 5)]);

    test('indexOfElement finds position, or -1', () {
      expect(layer.indexOfElement('a'), 0);
      expect(layer.indexOfElement('b'), 1);
      expect(layer.indexOfElement('nope'), -1);
    });

    test('elementById returns the element, or null', () {
      expect(layer.elementById('b')!.id, 'b');
      expect(layer.elementById('nope'), isNull);
    });
  });

  group('bounds', () {
    test('an empty layer has no bounds', () {
      expect(layerWith(const []).bounds, isNull);
    });

    test('unions every element', () {
      final layer = layerWith([rectAt('a', 0, 0), rectAt('b', 20, 30)]);
      expect(
        layer.bounds,
        const Bounds(left: 0, top: 0, right: 30, bottom: 40),
      );
    });

    test('skips elements that have no bounds of their own', () {
      final emptyStroke = Stroke(id: 'e', colorRGBA: 0, baseWidth: 1);
      final layer = layerWith([emptyStroke, rectAt('r', 5, 5)]);
      expect(
        layer.bounds,
        const Bounds(left: 5, top: 5, right: 15, bottom: 15),
      );
    });

    test('is null when every element lacks bounds', () {
      final layer = layerWith([Stroke(id: 'e', colorRGBA: 0, baseWidth: 1)]);
      expect(layer.bounds, isNull);
    });

    test('ignores visibility', () {
      final layer = layerWith([rectAt('a', 0, 0)]).copyWith(visible: false);
      expect(layer.bounds, isNotNull);
    });
  });

  group('addElement', () {
    test('appends on top and leaves the original alone', () {
      final original = layerWith([strokeAt('a', 0, 0)]);
      final grown = original.addElement(rectAt('b', 0, 0));

      expect(idsOf(grown), ['a', 'b']);
      expect(idsOf(original), ['a']);
    });
  });

  group('insertElement', () {
    final layer = layerWith([strokeAt('a', 0, 0), strokeAt('c', 0, 0)]);

    test('inserts at the given index, pushing later elements up', () {
      expect(idsOf(layer.insertElement(1, strokeAt('b', 0, 0))), [
        'a',
        'b',
        'c',
      ]);
    });

    test('index 0 inserts at the bottom of the stack', () {
      expect(idsOf(layer.insertElement(0, strokeAt('z', 0, 0))), [
        'z',
        'a',
        'c',
      ]);
    });

    test('index == elementCount appends', () {
      expect(idsOf(layer.insertElement(2, strokeAt('z', 0, 0))), [
        'a',
        'c',
        'z',
      ]);
    });

    test('rejects an out-of-range index', () {
      expect(
        () => layer.insertElement(-1, strokeAt('z', 0, 0)),
        throwsRangeError,
      );
      expect(
        () => layer.insertElement(3, strokeAt('z', 0, 0)),
        throwsRangeError,
      );
    });
  });

  group('removeElement', () {
    final layer = layerWith([strokeAt('a', 0, 0), strokeAt('b', 0, 0)]);

    test('removes by id, preserving order', () {
      expect(idsOf(layer.removeElement('a')), ['b']);
    });

    test('throws rather than silently succeeding on a missing id', () {
      expect(() => layer.removeElement('nope'), throwsArgumentError);
    });

    test('does not mutate the original', () {
      layer.removeElement('a');
      expect(idsOf(layer), ['a', 'b']);
    });
  });

  group('replaceElement', () {
    test('swaps in place, keeping z-order', () {
      final layer = layerWith([
        strokeAt('a', 0, 0),
        strokeAt('b', 0, 0),
        strokeAt('c', 0, 0),
      ]);
      final replaced = layer.replaceElement(rectAt('b', 99, 99));

      expect(idsOf(replaced), ['a', 'b', 'c']);
      expect(replaced.elements[1], isA<Shape>());
    });

    test('throws when no element carries that id', () {
      final layer = layerWith([strokeAt('a', 0, 0)]);
      expect(
        () => layer.replaceElement(rectAt('nope', 0, 0)),
        throwsArgumentError,
      );
    });
  });

  group('moveElement', () {
    final layer = layerWith([
      strokeAt('a', 0, 0),
      strokeAt('b', 0, 0),
      strokeAt('c', 0, 0),
    ]);

    test('indices address the resulting list', () {
      // Moving 'a' to index 2 puts it last, not second.
      expect(idsOf(layer.moveElement(0, 2)), ['b', 'c', 'a']);
    });

    test('moves upward in the stack', () {
      expect(idsOf(layer.moveElement(0, 1)), ['b', 'a', 'c']);
    });

    test('moves downward in the stack', () {
      expect(idsOf(layer.moveElement(2, 0)), ['c', 'a', 'b']);
    });

    test('moving to the same index is a no-op returning the same instance', () {
      expect(identical(layer.moveElement(1, 1), layer), isTrue);
    });

    test('rejects out-of-range indices', () {
      expect(() => layer.moveElement(-1, 0), throwsRangeError);
      expect(() => layer.moveElement(0, 3), throwsRangeError);
      expect(() => layer.moveElement(3, 0), throwsRangeError);
    });

    test('preserves the element set', () {
      expect(idsOf(layer.moveElement(0, 2))..sort(), ['a', 'b', 'c']);
    });
  });

  group('copyWith', () {
    final original = layerWith([strokeAt('a', 0, 0)]);

    test('replaces only the named fields', () {
      final renamed = original.copyWith(name: 'Sketch');
      expect(renamed.name, 'Sketch');
      expect(renamed.id, original.id);
      expect(idsOf(renamed), idsOf(original));
    });

    test('with no arguments returns an equal layer', () {
      expect(original.copyWith(), original);
    });

    test('can hide a layer without touching its elements', () {
      expect(original.copyWith(visible: false).elementCount, 1);
    });
  });

  group('value equality', () {
    test('identical field values are equal and share a hashCode', () {
      final a = layerWith([strokeAt('x', 1, 2)]);
      final b = layerWith([strokeAt('x', 1, 2)]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('compares elements deeply, not by reference', () {
      expect(
        layerWith([strokeAt('x', 1, 2)]),
        isNot(layerWith([strokeAt('x', 1, 3)])),
      );
    });

    test('element order participates in equality', () {
      final ab = layerWith([strokeAt('a', 0, 0), strokeAt('b', 0, 0)]);
      expect(ab, isNot(ab.moveElement(0, 1)));
    });

    test('opacity and visibility participate in equality', () {
      final base = layerWith(const []);
      expect(base, isNot(base.copyWith(opacity: 0.5)));
      expect(base, isNot(base.copyWith(visible: false)));
    });
  });
}
