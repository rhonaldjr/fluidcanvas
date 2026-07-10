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

Layer layer(String id, [List<CanvasElement> elements = const []]) =>
    Layer(id: id, name: id, elements: elements);

SkdDocument docWith(List<Layer> layers) =>
    SkdDocument(canvasWidth: 1920, canvasHeight: 1080, layers: layers);

List<String> layerIds(SkdDocument doc) => [for (final l in doc.layers) l.id];

void main() {
  group('newDefault', () {
    test('is 1920x1080 with one empty layer on a white background', () {
      final doc = SkdDocument.newDefault();
      expect(doc.canvasWidth, 1920);
      expect(doc.canvasHeight, 1080);
      expect(doc.backgroundRGBA, 0xFFFFFFFF);
      expect(doc.layerCount, 1);
      expect(doc.layers.single.name, 'Layer 1');
      expect(doc.isEmpty, isTrue);
      expect(doc.elementCount, 0);
    });

    test('generates a unique layer id when none is given', () {
      expect(
        SkdDocument.newDefault().layers.single.id,
        isNot(SkdDocument.newDefault().layers.single.id),
      );
    });

    test('accepts an explicit layer id, keeping tests deterministic', () {
      expect(
        SkdDocument.newDefault(layerId: 'fixed').layers.single.id,
        'fixed',
      );
    });

    test('honours a custom canvas size and background', () {
      final doc = SkdDocument.newDefault(
        canvasWidth: 800,
        canvasHeight: 600,
        backgroundRGBA: 0x000000FF,
      );
      expect(doc.canvasWidth, 800);
      expect(doc.canvasHeight, 600);
      expect(doc.backgroundRGBA, 0x000000FF);
    });
  });

  group('construction', () {
    test('rejects a non-positive canvas', () {
      expect(
        () =>
            SkdDocument(canvasWidth: 0, canvasHeight: 10, layers: [layer('a')]),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => SkdDocument(
          canvasWidth: 10,
          canvasHeight: -1,
          layers: [layer('a')],
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects a document with no layers', () {
      // DeleteLayerCommand disallows removing the last layer; this is the
      // invariant that rule protects. The reader validates it again, since
      // asserts vanish in release builds.
      expect(
        () => SkdDocument(canvasWidth: 10, canvasHeight: 10, layers: const []),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects duplicate layer ids', () {
      expect(
        () => docWith([layer('dup'), layer('dup')]),
        throwsA(isA<AssertionError>()),
      );
    });

    test('layers are unmodifiable', () {
      final doc = docWith([layer('a')]);
      expect(() => doc.layers.add(layer('b')), throwsUnsupportedError);
    });

    test('copies the incoming list, so caller mutation cannot leak in', () {
      final source = [layer('a')];
      final doc = docWith(source);
      source.add(layer('b'));
      expect(doc.layerCount, 1);
    });
  });

  group('counts', () {
    test('elementCount sums every layer', () {
      final doc = docWith([
        layer('a', [strokeAt('s1', 0, 0), strokeAt('s2', 0, 0)]),
        layer('b', [rectAt('r1', 0, 0)]),
      ]);
      expect(doc.elementCount, 3);
    });

    test('isEmpty is true only when no layer holds anything', () {
      expect(docWith([layer('a'), layer('b')]).isEmpty, isTrue);
      expect(
        docWith([
          layer('a'),
          layer('b', [rectAt('r', 0, 0)]),
        ]).isEmpty,
        isFalse,
      );
    });

    test('isEmpty ignores visibility', () {
      final hidden = layer('a', [rectAt('r', 0, 0)]).copyWith(visible: false);
      expect(docWith([hidden]).isEmpty, isFalse);
    });
  });

  group('layer lookup', () {
    final doc = docWith([layer('bottom'), layer('top')]);

    test('indexOfLayer reports bottom-to-top position, or -1', () {
      expect(doc.indexOfLayer('bottom'), 0);
      expect(doc.indexOfLayer('top'), 1);
      expect(doc.indexOfLayer('nope'), -1);
    });

    test('layerById returns the layer, or null', () {
      expect(doc.layerById('top')!.id, 'top');
      expect(doc.layerById('nope'), isNull);
    });
  });

  group('findElement', () {
    test('returns the element and its owning layer', () {
      final doc = docWith([
        layer('bottom', [strokeAt('s', 0, 0)]),
        layer('top', [rectAt('r', 0, 0)]),
      ]);

      final found = doc.findElement('r')!;
      expect(found.element.id, 'r');
      expect(found.layer.id, 'top');

      final deeper = doc.findElement('s')!;
      expect(deeper.layer.id, 'bottom');
      expect(deeper.element, isA<Stroke>());
    });

    test('returns null for an unknown id', () {
      expect(
        docWith([
          layer('a', [rectAt('r', 0, 0)]),
        ]).findElement('nope'),
        isNull,
      );
    });

    test('searches top-down, as a click would', () {
      // Ids are unique in practice, but if one ever repeats the topmost wins,
      // matching what the user sees.
      final doc = docWith([
        layer('bottom', [strokeAt('same', 0, 0)]),
        layer('top', [rectAt('same', 0, 0)]),
      ]);
      expect(doc.findElement('same')!.layer.id, 'top');
    });

    test('finds nothing in an empty document', () {
      expect(SkdDocument.newDefault().findElement('anything'), isNull);
    });
  });

  group('replaceLayer', () {
    final doc = docWith([layer('a'), layer('b'), layer('c')]);

    test('swaps in place, preserving stack order', () {
      final replaced = doc.replaceLayer(layer('b', [rectAt('r', 0, 0)]));
      expect(layerIds(replaced), ['a', 'b', 'c']);
      expect(replaced.layerById('b')!.elementCount, 1);
    });

    test('does not mutate the original', () {
      doc.replaceLayer(layer('b', [rectAt('r', 0, 0)]));
      expect(doc.layerById('b')!.elementCount, 0);
    });

    test('throws rather than silently no-opping on a missing id', () {
      expect(() => doc.replaceLayer(layer('nope')), throwsArgumentError);
    });

    test('carries canvas size and background through', () {
      final custom = SkdDocument(
        canvasWidth: 800,
        canvasHeight: 600,
        backgroundRGBA: 0x112233FF,
        layers: [layer('a')],
      );
      final replaced = custom.replaceLayer(layer('a', [rectAt('r', 0, 0)]));
      expect(replaced.canvasWidth, 800);
      expect(replaced.canvasHeight, 600);
      expect(replaced.backgroundRGBA, 0x112233FF);
    });
  });

  group('bounds', () {
    test('is null when nothing has bounds', () {
      expect(SkdDocument.newDefault().bounds, isNull);
    });

    test('unions across layers', () {
      final doc = docWith([
        layer('a', [rectAt('r1', 0, 0)]),
        layer('b', [rectAt('r2', 40, 50)]),
      ]);
      expect(doc.bounds, const Bounds(left: 0, top: 0, right: 50, bottom: 60));
    });

    test('may extend beyond the canvas', () {
      final doc = SkdDocument(
        canvasWidth: 10,
        canvasHeight: 10,
        layers: [
          layer('a', [rectAt('r', 100, 100)]),
        ],
      );
      expect(doc.bounds!.right, 110);
    });

    test('ignores layer visibility', () {
      final hidden = layer('a', [rectAt('r', 0, 0)]).copyWith(visible: false);
      expect(docWith([hidden]).bounds, isNotNull);
    });
  });

  group('copyWith', () {
    final original = docWith([layer('a')]);

    test('replaces only the named fields', () {
      final resized = original.copyWith(canvasWidth: 800);
      expect(resized.canvasWidth, 800);
      expect(resized.canvasHeight, original.canvasHeight);
      expect(layerIds(resized), layerIds(original));
    });

    test('with no arguments returns an equal document', () {
      expect(original.copyWith(), original);
    });
  });

  group('value equality', () {
    test('identical field values are equal and share a hashCode', () {
      final a = docWith([
        layer('l', [strokeAt('s', 1, 2)]),
      ]);
      final b = docWith([
        layer('l', [strokeAt('s', 1, 2)]),
      ]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('compares layers deeply, down to element geometry', () {
      final a = docWith([
        layer('l', [strokeAt('s', 1, 2)]),
      ]);
      final b = docWith([
        layer('l', [strokeAt('s', 1, 3)]),
      ]);
      expect(a, isNot(b));
    });

    test('layer order participates in equality', () {
      expect(
        docWith([layer('a'), layer('b')]),
        isNot(docWith([layer('b'), layer('a')])),
      );
    });

    test('canvas size and background participate in equality', () {
      final base = docWith([layer('a')]);
      expect(base, isNot(base.copyWith(canvasWidth: 800)));
      expect(base, isNot(base.copyWith(backgroundRGBA: 0x000000FF)));
    });
  });
}
