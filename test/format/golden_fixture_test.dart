import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/format/format.dart';

/// `test/fixtures/v1_golden.skd` was written once, hand-verified with `unzip`
/// and Python's `zipfile`, and committed. It must load forever.
///
/// This is the backward-compatibility lock: if a change to the codec breaks it,
/// that change breaks every `.skd` anyone has ever saved.
///
/// It deliberately asserts the *model*, never rendered pixels — the text
/// element names a system font, so glyphs and line breaks differ per machine.
const _path = 'test/fixtures/v1_golden.skd';

String Function() counter() {
  var n = 0;
  return () => 'e${n++}';
}

void main() {
  test('the fixture exists and is committed', () {
    expect(File(_path).existsSync(), isTrue);
  });

  group('v1 golden fixture', () {
    late SkdFile file;

    setUp(() {
      file = decodeSkd(File(_path).readAsBytesSync(), idFor: counter());
    });

    test('loads', () {
      expect(file.manifest.formatVersion, 1);
      expect(file.manifest.appVersion, '0.1.0');
    });

    test('the canvas survives', () {
      expect(file.document.canvasWidth, 800);
      expect(file.document.canvasHeight, 600);
      expect(file.document.backgroundRGBA, 0xFFFFFFFF);
    });

    test('three layers, bottom to top, with their properties', () {
      final layers = file.document.layers;
      expect([for (final l in layers) l.id], ['layer-1', 'layer-2', 'layer-3']);
      expect(layers[1].opacity, 0.75);
      expect(layers[1].blendMode, LayerBlendMode.multiply);
      expect(layers[2].name, 'Text');
    });

    test('strokes: a pen stroke with pressure, and an eraser', () {
      final elements = file.document.layers.first.elements;
      expect(elements, hasLength(2));

      final pen = elements[0] as Stroke;
      expect(pen.colorRGBA, 0x1B1B1FFF);
      expect(pen.baseWidth, 4);
      expect(pen.points, hasLength(3));
      expect(pen.points.first.pressure, 0.25);
      expect(pen.isEraser, isFalse);

      expect((elements[1] as Stroke).isEraser, isTrue);
    });

    test('one of every shape type, with fills, dashes and a rotation', () {
      final shapes = file.document.layers[1].elements.cast<Shape>();
      expect([for (final s in shapes) s.type], ShapeType.values);

      expect(shapes[0].isFilled, isTrue);
      expect(shapes[1].isFilled, isFalse);
      expect(shapes[0].strokeStyle, StrokeStyle.solid);
      expect(shapes[1].strokeStyle, StrokeStyle.dashed);
      expect(shapes[2].strokeStyle, StrokeStyle.dotted);
      expect(shapes[4].rotation, closeTo(0.25, 1e-6));
    });

    test('text with mixed runs and non-ASCII', () {
      final text = file.document.layers[2].elements.single as TextElement;

      expect(text.fontFamily, 'Helvetica');
      expect(text.fontSize, 22);
      expect(text.align, TextAlignment.left);
      expect(text.text, contains('ünïcødé 😀'));

      final styled = {for (final run in text.runs) run.text: run.styleFlags};
      expect(styled['bold'], 1);
      expect(styled['italic'], 2);
      expect(styled['underlined'], 4);
    });

    test('element ids are regenerated, never read from the file', () {
      final ids = [
        for (final layer in file.document.layers)
          for (final element in layer.elements) element.id,
      ];
      expect(ids, ['e0', 'e1', 'e2', 'e3', 'e4', 'e5', 'e6', 'e7']);
    });

    test('re-encoding the loaded document round-trips to the same model', () {
      // The bytes need not be identical — timestamps live in the manifest —
      // but the document must survive another lap.
      final again = decodeSkd(
        encodeSkd(file.document, manifest: file.manifest),
        idFor: counter(),
      ).document;

      expect(again.canvasWidth, file.document.canvasWidth);
      expect(again.elementCount, file.document.elementCount);
      expect(again.layers[1].blendMode, LayerBlendMode.multiply);
      expect(
        (again.layers[2].elements.single as TextElement).text,
        (file.document.layers[2].elements.single as TextElement).text,
      );
    });
  });
}
