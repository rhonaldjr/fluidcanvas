import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/renderer/document_painter.dart';

Stroke strokeLine(String id) => Stroke(
  id: id,
  colorRGBA: 0x000000FF,
  baseWidth: 4,
  points: const [StrokePoint(x: 0, y: 0), StrokePoint(x: 100, y: 100)],
);

Shape rect(String id) => Shape(
  id: id,
  type: ShapeType.rectangle,
  x: 0,
  y: 0,
  w: 50,
  h: 50,
  strokeColorRGBA: 0x000000FF,
  strokeWidth: 2,
);

SkdDocument docWith(List<Layer> layers) =>
    SkdDocument(canvasWidth: 200, canvasHeight: 200, layers: layers);

int recordedBytes(DocumentPainter painter) {
  final recorder = PictureRecorder();
  painter.paint(Canvas(recorder), const Size(200, 200));
  return recorder.endRecording().approximateBytesUsed;
}

void main() {
  group('colorFromRGBA', () {
    test('unpacks 0xRRGGBBAA into ARGB', () {
      // Opaque red.
      const red = Color(0xFFFF0000);
      expect(colorFromRGBA(0xFF0000FF), red);
    });

    test('alpha comes from the low byte', () {
      expect(colorFromRGBA(0x00000000).a, 0);
      expect(colorFromRGBA(0x000000FF).a, 1.0);
    });

    test('channels do not bleed into one another', () {
      const c = Color(0xFF112233);
      expect(colorFromRGBA(0x112233FF), c);
    });

    test('round-trips the default stroke colour', () {
      expect(colorFromRGBA(0x1B1B1FFF), const Color(0xFF1B1B1F));
    });
  });

  group('paint', () {
    // Recorded op size, not pixels: CLAUDE.md says no pixel goldens here.
    late int emptyBytes;

    setUp(() {
      emptyBytes = recordedBytes(
        DocumentPainter(
          document: docWith([Layer(id: 'a', name: 'a')]),
          scale: 1,
        ),
      );
    });

    test('an empty document paints nothing', () {
      final same = recordedBytes(
        DocumentPainter(
          document: docWith([Layer(id: 'b', name: 'b')]),
          scale: 1,
        ),
      );
      expect(same, emptyBytes);
    });

    test('a stroke paints', () {
      expect(
        recordedBytes(
          DocumentPainter(
            document: docWith([
              Layer(id: 'a', name: 'a', elements: [strokeLine('s')]),
            ]),
            scale: 1,
          ),
        ),
        greaterThan(emptyBytes),
      );
    });

    test('a hidden layer paints nothing', () {
      final hidden = Layer(
        id: 'a',
        name: 'a',
        visible: false,
        elements: [strokeLine('s')],
      );
      expect(
        recordedBytes(DocumentPainter(document: docWith([hidden]), scale: 1)),
        emptyBytes,
      );
    });

    test('a fully transparent layer paints nothing', () {
      final invisible = Layer(
        id: 'a',
        name: 'a',
        opacity: 0,
        elements: [strokeLine('s')],
      );
      expect(
        recordedBytes(
          DocumentPainter(document: docWith([invisible]), scale: 1),
        ),
        emptyBytes,
      );
    });

    test('nothing paints at zero scale', () {
      // Returns before touching the canvas, so it records even less than the
      // empty-document baseline, which still emits save/scale/restore.
      expect(
        recordedBytes(
          DocumentPainter(
            document: docWith([
              Layer(id: 'a', name: 'a', elements: [strokeLine('s')]),
            ]),
            scale: 0,
          ),
        ),
        lessThanOrEqualTo(emptyBytes),
      );
    });

    test('shapes are skipped until task 8.2, without crashing', () {
      final withShape = docWith([
        Layer(id: 'a', name: 'a', elements: [rect('r')]),
      ]);
      expect(
        () => recordedBytes(DocumentPainter(document: withShape, scale: 1)),
        returnsNormally,
      );
      expect(
        recordedBytes(DocumentPainter(document: withShape, scale: 1)),
        emptyBytes,
      );
    });

    test('an empty stroke is skipped', () {
      final empty = Stroke(id: 'e', colorRGBA: 0, baseWidth: 1);
      expect(
        recordedBytes(
          DocumentPainter(
            document: docWith([
              Layer(id: 'a', name: 'a', elements: [empty]),
            ]),
            scale: 1,
          ),
        ),
        emptyBytes,
      );
    });

    test('a single-point stroke paints a dot', () {
      final dot = Stroke(
        id: 'd',
        colorRGBA: 0x000000FF,
        baseWidth: 8,
        points: const [StrokePoint(x: 50, y: 50)],
      );
      expect(
        recordedBytes(
          DocumentPainter(
            document: docWith([
              Layer(id: 'a', name: 'a', elements: [dot]),
            ]),
            scale: 1,
          ),
        ),
        greaterThan(emptyBytes),
      );
    });
  });

  group('shouldRepaint', () {
    final document = docWith([Layer(id: 'a', name: 'a')]);

    test('does not repaint for the same document and scale', () {
      final a = DocumentPainter(document: document, scale: 1);
      final b = DocumentPainter(document: document, scale: 1);
      expect(b.shouldRepaint(a), isFalse);
    });

    test('repaints when the document instance changes', () {
      final a = DocumentPainter(document: document, scale: 1);
      final b = DocumentPainter(
        document: document.replaceLayer(
          Layer(id: 'a', name: 'a', elements: [strokeLine('s')]),
        ),
        scale: 1,
      );
      expect(b.shouldRepaint(a), isTrue);
    });

    test('repaints when the scale changes', () {
      expect(
        DocumentPainter(
          document: document,
          scale: 0.5,
        ).shouldRepaint(DocumentPainter(document: document, scale: 1)),
        isTrue,
      );
    });
  });
}
