import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/renderer/layer_cache.dart';
import 'package:inkpad/engine/renderer/layer_stack_painter.dart';

Stroke stroke(String id) => Stroke(
  id: id,
  colorRGBA: 0xFF,
  baseWidth: 4,
  points: const [
    StrokePoint(x: 0, y: 0, pressure: 1),
    StrokePoint(x: 20, y: 20, pressure: 1),
  ],
);

TextElement text(String id) =>
    TextElement.plain(id: id, x: 5, y: 5, w: 100, h: 40, text: 'hi');

void paintLayer(Layer layer, LayerCache cache) {
  final painter = LayerStackPainter(
    layers: [layer],
    documentWidth: 200,
    documentHeight: 100,
    scale: 1,
    cache: cache,
  );
  final rec = ui.PictureRecorder();
  painter.paint(Canvas(rec), const Size(200, 100));
  rec.endRecording().dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('layerHasText', () {
    test('is true for a text element', () {
      expect(elementHasText(text('t')), isTrue);
    });

    test('is false for strokes, shapes and connectors', () {
      expect(elementHasText(stroke('s')), isFalse);
      expect(
        elementHasText(
          const Shape(
            id: 's',
            type: ShapeType.rectangle,
            x: 0,
            y: 0,
            w: 1,
            h: 1,
            strokeColorRGBA: 0,
            strokeWidth: 1,
          ),
        ),
        isFalse,
      );
      expect(
        elementHasText(
          Connector(
            id: 'c',
            start: const ConnectorEnd.free(0, 0),
            end: const ConnectorEnd.free(1, 1),
            strokeColorRGBA: 0,
            strokeWidth: 1,
          ),
        ),
        isFalse,
      );
    });

    test('sees text nested inside a group', () {
      final withText = Group(id: 'g', children: [stroke('s'), text('t')]);
      final withoutText = Group(id: 'g', children: [stroke('a'), stroke('b')]);
      expect(elementHasText(withText), isTrue);
      expect(elementHasText(withoutText), isFalse);
    });

    test('a layer reports whether any element is text', () {
      expect(
        layerHasText(Layer(id: 'L', name: 'L', elements: [stroke('s')])),
        isFalse,
      );
      expect(
        layerHasText(
          Layer(id: 'L', name: 'L', elements: [stroke('s'), text('t')]),
        ),
        isTrue,
      );
    });
  });

  group('text layers bypass the toImageSync cache', () {
    // The bug this guards: `Picture.toImageSync` drops text glyphs on the real
    // renderer, so a layer holding text must be painted live. It is served from
    // the cache only if it has none.
    test('a text layer is never cached', () {
      final cache = LayerCache();
      paintLayer(Layer(id: 'L', name: 'L', elements: [text('t')]), cache);
      expect(cache.length, 0, reason: 'the text layer must render live');
    });

    test('a stroke-only layer is cached', () {
      final cache = LayerCache();
      paintLayer(Layer(id: 'L', name: 'L', elements: [stroke('s')]), cache);
      expect(cache.length, 1, reason: 'no text, so the fast cache is used');
    });

    test('a mixed layer with any text bypasses the cache', () {
      final cache = LayerCache();
      paintLayer(
        Layer(id: 'L', name: 'L', elements: [stroke('s'), text('t')]),
        cache,
      );
      expect(cache.length, 0);
    });

    test('a group holding text bypasses the cache', () {
      final cache = LayerCache();
      paintLayer(
        Layer(
          id: 'L',
          name: 'L',
          elements: [
            Group(id: 'g', children: [stroke('a'), text('t')]),
          ],
        ),
        cache,
      );
      expect(cache.length, 0);
    });
  });

  group('text isolation decision (the saveLayer that blanked glyphs)', () {
    Layer withText({double opacity = 1.0, bool eraser = false}) => Layer(
      id: 'L',
      name: 'L',
      opacity: opacity,
      elements: [
        text('t'),
        if (eraser)
          Stroke(
            id: 'e',
            colorRGBA: 0,
            baseWidth: 4,
            toolId: ToolId.eraser,
            points: const [
              StrokePoint(x: 0, y: 0, pressure: 1),
              StrokePoint(x: 5, y: 5, pressure: 1),
            ],
          ),
      ],
    );

    test('a full-opacity, eraser-free text layer needs no saveLayer', () {
      // This is the case that was blanking committed text: it must draw direct.
      expect(textLayerNeedsIsolation(withText()), isFalse);
    });

    test('a dimmed text layer needs isolation', () {
      expect(textLayerNeedsIsolation(withText(opacity: 0.5)), isTrue);
    });

    test('a text layer with an eraser needs isolation', () {
      expect(textLayerNeedsIsolation(withText(eraser: true)), isTrue);
    });

    test('a live eraser forces isolation even on a clean text layer', () {
      final live = Stroke(
        id: 'live',
        colorRGBA: 0,
        baseWidth: 4,
        toolId: ToolId.eraser,
      );
      expect(textLayerNeedsIsolation(withText(), live: live), isTrue);
    });

    test('a live pen does not force isolation', () {
      final live = Stroke(id: 'live', colorRGBA: 0xFF, baseWidth: 4);
      expect(textLayerNeedsIsolation(withText(), live: live), isFalse);
    });
  });
}
