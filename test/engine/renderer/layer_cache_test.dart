import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/renderer/layer_cache.dart';

Stroke strokeAt(String id, double x) => Stroke(
  id: id,
  colorRGBA: 0x000000FF,
  baseWidth: 6,
  points: [
    StrokePoint(x: x, y: 10),
    StrokePoint(x: x + 40, y: 60),
  ],
);

Layer layerWith(List<CanvasElement> elements, {String id = 'l'}) =>
    Layer(id: id, name: id, elements: elements);

void main() {
  late LayerCache cache;

  setUp(() => cache = LayerCache());
  tearDown(() => cache.dispose());

  group('Layer keeps its element list identity', () {
    // The cache keys on this. Without it, renaming a layer or nudging its
    // opacity would throw away an 8 MB image.
    test('copyWith without elements reuses the same list', () {
      final layer = layerWith([strokeAt('a', 0)]);
      expect(
        identical(layer.copyWith(name: 'x').elements, layer.elements),
        isTrue,
      );
      expect(
        identical(layer.copyWith(opacity: 0.5).elements, layer.elements),
        isTrue,
      );
      expect(
        identical(layer.copyWith(visible: false).elements, layer.elements),
        isTrue,
      );
    });

    test('changing the elements yields a different list', () {
      final layer = layerWith([strokeAt('a', 0)]);
      final grown = layer.addElement(strokeAt('b', 50));
      expect(identical(grown.elements, layer.elements), isFalse);
    });

    test('a caller list is still copied, so it cannot leak in', () {
      final source = <CanvasElement>[strokeAt('a', 0)];
      final layer = layerWith(source);
      source.add(strokeAt('b', 10));
      expect(layer.elementCount, 1);
    });
  });

  group('imageFor', () {
    test('rasterizes at the requested size', () {
      final image = cache.imageFor(
        layerWith([strokeAt('a', 0)]),
        width: 200,
        height: 100,
      );
      expect(image.width, 200);
      expect(image.height, 100);
    });

    test('the same layer is served from cache', () {
      final layer = layerWith([strokeAt('a', 0)]);
      final first = cache.imageFor(layer, width: 100, height: 100);
      final second = cache.imageFor(layer, width: 100, height: 100);
      expect(identical(first, second), isTrue);
    });

    test('a rename or opacity change is a cache hit', () {
      final layer = layerWith([strokeAt('a', 0)]);
      final first = cache.imageFor(layer, width: 100, height: 100);

      expect(
        cache.isCached(
          layer.copyWith(name: 'renamed'),
          width: 100,
          height: 100,
        ),
        isTrue,
      );
      final second = cache.imageFor(
        layer.copyWith(opacity: 0.3),
        width: 100,
        height: 100,
      );
      expect(identical(first, second), isTrue);
    });

    test('adding an element invalidates the layer', () {
      final layer = layerWith([strokeAt('a', 0)]);
      final first = cache.imageFor(layer, width: 100, height: 100);

      final grown = layer.addElement(strokeAt('b', 40));
      expect(cache.isCached(grown, width: 100, height: 100), isFalse);
      expect(
        identical(cache.imageFor(grown, width: 100, height: 100), first),
        isFalse,
      );
    });

    test('a different size invalidates the layer', () {
      final layer = layerWith([strokeAt('a', 0)]);
      cache.imageFor(layer, width: 100, height: 100);
      expect(cache.isCached(layer, width: 200, height: 100), isFalse);
    });

    test('layers are cached independently', () {
      final a = layerWith([strokeAt('a', 0)], id: 'a');
      final b = layerWith([strokeAt('b', 0)], id: 'b');
      cache
        ..imageFor(a, width: 50, height: 50)
        ..imageFor(b, width: 50, height: 50);
      expect(cache.length, 2);

      final grownA = a.addElement(strokeAt('a2', 20));
      cache.imageFor(grownA, width: 50, height: 50);
      // b was untouched.
      expect(cache.isCached(b, width: 50, height: 50), isTrue);
    });

    test('an empty layer still rasterizes without crashing', () {
      expect(
        () => cache.imageFor(layerWith(const []), width: 20, height: 20),
        returnsNormally,
      );
    });
  });

  group('retainOnly', () {
    test('drops layers no longer in the document', () {
      cache
        ..imageFor(
          layerWith([strokeAt('a', 0)], id: 'a'),
          width: 40,
          height: 40,
        )
        ..imageFor(
          layerWith([strokeAt('b', 0)], id: 'b'),
          width: 40,
          height: 40,
        );
      expect(cache.length, 2);

      cache.retainOnly(['a']);
      expect(cache.length, 1);
    });

    test('keeps everything when all ids are retained', () {
      cache.imageFor(
        layerWith([strokeAt('a', 0)], id: 'a'),
        width: 40,
        height: 40,
      );
      cache.retainOnly(['a', 'b']);
      expect(cache.length, 1);
    });
  });

  group('renderLayerToImage', () {
    Future<int> alphaAt(Layer layer, int x, int y) async {
      final image = renderLayerToImage(layer, 200, 200);
      final data = (await image.toByteData())!;
      final alpha = data.getUint8((y * 200 + x) * 4 + 3);
      image.dispose();
      return alpha;
    }

    Stroke inkAcross(String id) => Stroke(
      id: id,
      colorRGBA: 0x000000FF,
      baseWidth: 30,
      points: const [StrokePoint(x: 0, y: 100), StrokePoint(x: 200, y: 100)],
    );

    Stroke eraserAcross(String id) => Stroke(
      id: id,
      colorRGBA: 0,
      baseWidth: 30,
      toolId: ToolId.eraser,
      points: const [StrokePoint(x: 0, y: 100), StrokePoint(x: 200, y: 100)],
    );

    test('ink is opaque, empty space is transparent', () async {
      final layer = layerWith([inkAcross('s')]);
      expect(await alphaAt(layer, 100, 100), 255);
      expect(await alphaAt(layer, 100, 10), 0);
    });

    test('an eraser clears within the image, needing no saveLayer', () async {
      // The image *is* the layer buffer, so clear works straight into it.
      final layer = layerWith([inkAcross('s'), eraserAcross('e')]);
      expect(await alphaAt(layer, 100, 100), 0);
    });

    test('layer opacity is not baked in', () async {
      // Otherwise an opacity drag would invalidate the cache every frame.
      final layer = layerWith([inkAcross('s')]).copyWith(opacity: 0.25);
      expect(await alphaAt(layer, 100, 100), 255);
    });

    test(
      'a hidden layer still rasterizes; visibility is applied on composite',
      () async {
        final layer = layerWith([inkAcross('s')]).copyWith(visible: false);
        expect(await alphaAt(layer, 100, 100), 255);
      },
    );
  });

  group('incremental append', () {
    Stroke inkAt(String id, double y) => Stroke(
      id: id,
      colorRGBA: 0x000000FF,
      baseWidth: 20,
      points: [
        StrokePoint(x: 0, y: y),
        StrokePoint(x: 200, y: y),
      ],
    );

    Stroke eraserAt(String id, double y) => Stroke(
      id: id,
      colorRGBA: 0,
      baseWidth: 20,
      toolId: ToolId.eraser,
      points: [
        StrokePoint(x: 0, y: y),
        StrokePoint(x: 200, y: y),
      ],
    );

    Future<int> alphaAt(ui.Image image, int x, int y) async {
      final data = (await image.toByteData())!;
      return data.getUint8((y * 200 + x) * 4 + 3);
    }

    test('appending a stroke keeps the earlier ones drawn', () async {
      final layer = layerWith([inkAt('a', 50)]);
      cache.imageFor(layer, width: 200, height: 200);

      final grown = layer.addElement(inkAt('b', 150));
      final image = cache.imageFor(grown, width: 200, height: 200);

      // Both strokes are present: the old one came from the cached image, the
      // new one was painted on top of it.
      expect(await alphaAt(image, 100, 50), 255);
      expect(await alphaAt(image, 100, 150), 255);
      expect(await alphaAt(image, 100, 100), 0);
    });

    test('an appended eraser clears the cached ink beneath it', () async {
      final layer = layerWith([inkAt('a', 50)]);
      cache.imageFor(layer, width: 200, height: 200);

      final erased = layer.addElement(eraserAt('e', 50));
      final image = cache.imageFor(erased, width: 200, height: 200);

      expect(await alphaAt(image, 100, 50), 0);
    });

    test('the incremental result matches a full render', () async {
      final layer = layerWith([inkAt('a', 50)]);
      cache.imageFor(layer, width: 200, height: 200);
      final grown = layer.addElement(inkAt('b', 150));
      final incremental = cache.imageFor(grown, width: 200, height: 200);

      final fresh = LayerCache();
      final full = fresh.imageFor(grown, width: 200, height: 200);

      for (final (x, y) in [(100, 50), (100, 150), (100, 100), (5, 50)]) {
        expect(
          await alphaAt(incremental, x, y),
          await alphaAt(full, x, y),
          reason: 'pixel ($x, $y)',
        );
      }
      fresh.dispose();
    });

    test('removing an element falls back to a full render', () async {
      // An undo is not an append: the cached image cannot be extended, because
      // paint already committed cannot be taken back out of it.
      final layer = layerWith([inkAt('a', 50), inkAt('b', 150)]);
      cache.imageFor(layer, width: 200, height: 200);

      final undone = layer.removeElement('b');
      final image = cache.imageFor(undone, width: 200, height: 200);

      expect(await alphaAt(image, 100, 50), 255);
      expect(await alphaAt(image, 100, 150), 0);
    });

    test('reordering falls back to a full render', () async {
      final layer = layerWith([inkAt('a', 50), inkAt('b', 150)]);
      cache.imageFor(layer, width: 200, height: 200);

      final reordered = layer.moveElement(0, 1);
      final image = cache.imageFor(reordered, width: 200, height: 200);
      expect(await alphaAt(image, 100, 50), 255);
      expect(await alphaAt(image, 100, 150), 255);
    });

    test('replacing an element falls back to a full render', () async {
      final layer = layerWith([inkAt('a', 50)]);
      cache.imageFor(layer, width: 200, height: 200);

      final moved = layer.replaceElement(inkAt('a', 150));
      final image = cache.imageFor(moved, width: 200, height: 200);
      expect(await alphaAt(image, 100, 50), 0);
      expect(await alphaAt(image, 100, 150), 255);
    });

    test('a resized document falls back to a full render', () {
      final layer = layerWith([inkAt('a', 50)]);
      cache.imageFor(layer, width: 200, height: 200);
      final grown = layer.addElement(inkAt('b', 150));
      final image = cache.imageFor(grown, width: 300, height: 300);
      expect(image.width, 300);
    });
  });
}
