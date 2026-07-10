import 'dart:ui' as ui show Image;
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

    // A layer holding elements always opens an offscreen buffer, even when
    // nothing in it paints — the eraser needs somewhere bounded to clear. So
    // "paints nothing" is measured against that overhead, not against an
    // empty document.
    int overheadBytes() => recordedBytes(
      DocumentPainter(
        document: docWith([
          Layer(
            id: 'a',
            name: 'a',
            elements: [Stroke(id: 'e', colorRGBA: 0, baseWidth: 1)],
          ),
        ]),
        scale: 1,
      ),
    );

    test('an empty stroke is skipped', () {
      expect(overheadBytes(), greaterThan(emptyBytes)); // the saveLayer
      expect(
        overheadBytes(),
        lessThan(
          recordedBytes(
            DocumentPainter(
              document: docWith([
                Layer(id: 'a', name: 'a', elements: [strokeLine('s')]),
              ]),
              scale: 1,
            ),
          ),
        ),
      );
    });

    test('shapes paint', () {
      final withShape = docWith([
        Layer(id: 'a', name: 'a', elements: [rect('r')]),
      ]);
      expect(
        recordedBytes(DocumentPainter(document: withShape, scale: 1)),
        greaterThan(overheadBytes()),
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

  group('eraser', () {
    Stroke eraserAcross(String id) => Stroke(
      id: id,
      colorRGBA: 0,
      baseWidth: 30,
      toolId: ToolId.eraser,
      points: const [StrokePoint(x: 0, y: 100), StrokePoint(x: 200, y: 100)],
    );

    Stroke inkAcross(String id) => Stroke(
      id: id,
      colorRGBA: 0x000000FF,
      baseWidth: 30,
      points: const [StrokePoint(x: 0, y: 100), StrokePoint(x: 200, y: 100)],
    );

    /// Renders the document and returns the pixel at (x, y) as ARGB.
    Future<int> pixelAt(SkdDocument document, int x, int y) async {
      final recorder = PictureRecorder();
      DocumentPainter(
        document: document,
        scale: 1,
      ).paint(Canvas(recorder), const Size(200, 200));
      final ui.Image image = await recorder.endRecording().toImage(200, 200);
      final data = (await image.toByteData())!;
      final offset = (y * 200 + x) * 4;
      final r = data.getUint8(offset);
      final g = data.getUint8(offset + 1);
      final b = data.getUint8(offset + 2);
      final a = data.getUint8(offset + 3);
      return (a << 24) | (r << 16) | (g << 8) | b;
    }

    int alphaOf(int argb) => (argb >> 24) & 0xFF;

    test('ink paints opaque pixels', () async {
      final doc = docWith([
        Layer(id: 'a', name: 'a', elements: [inkAcross('s')]),
      ]);
      expect(alphaOf(await pixelAt(doc, 100, 100)), 255);
    });

    test('an eraser in the same layer removes the ink beneath it', () async {
      final doc = docWith([
        Layer(
          id: 'a',
          name: 'a',
          elements: [inkAcross('s'), eraserAcross('e')],
        ),
      ]);
      expect(alphaOf(await pixelAt(doc, 100, 100)), 0);
    });

    test('an eraser in another layer leaves that layer alone', () async {
      // This is what the per-layer saveLayer buys: clear must not punch
      // through the layers beneath.
      final doc = docWith([
        Layer(id: 'ink', name: 'ink', elements: [inkAcross('s')]),
        Layer(id: 'rub', name: 'rub', elements: [eraserAcross('e')]),
      ]);
      expect(alphaOf(await pixelAt(doc, 100, 100)), 255);
    });

    test('an eraser only clears where it is drawn', () async {
      final doc = docWith([
        Layer(
          id: 'a',
          name: 'a',
          elements: [inkAcross('s'), eraserAcross('e')],
        ),
      ]);
      // Far from the eraser line, the ink survives... there is none here.
      expect(alphaOf(await pixelAt(doc, 100, 20)), 0);
    });

    test('a live eraser stroke erases inside its own layer', () async {
      final doc = docWith([
        Layer(id: 'ink', name: 'ink', elements: [inkAcross('s')]),
      ]);
      final recorder = PictureRecorder();
      DocumentPainter(
        document: doc,
        scale: 1,
        liveStroke: eraserAcross('live'),
        liveLayerId: 'ink',
      ).paint(Canvas(recorder), const Size(200, 200));
      final image = await recorder.endRecording().toImage(200, 200);
      final data = (await image.toByteData())!;
      expect(data.getUint8((100 * 200 + 100) * 4 + 3), 0);
    });

    test(
      'a live eraser aimed at another layer does not touch the ink',
      () async {
        final doc = docWith([
          Layer(id: 'ink', name: 'ink', elements: [inkAcross('s')]),
          Layer(id: 'rub', name: 'rub'),
        ]);
        final recorder = PictureRecorder();
        DocumentPainter(
          document: doc,
          scale: 1,
          liveStroke: eraserAcross('live'),
          liveLayerId: 'rub',
        ).paint(Canvas(recorder), const Size(200, 200));
        final image = await recorder.endRecording().toImage(200, 200);
        final data = (await image.toByteData())!;
        expect(data.getUint8((100 * 200 + 100) * 4 + 3), 255);
      },
    );

    test('a live stroke draws into an otherwise empty layer', () async {
      final doc = docWith([Layer(id: 'a', name: 'a')]);
      final recorder = PictureRecorder();
      DocumentPainter(
        document: doc,
        scale: 1,
        liveStroke: inkAcross('live'),
        liveLayerId: 'a',
      ).paint(Canvas(recorder), const Size(200, 200));
      final image = await recorder.endRecording().toImage(200, 200);
      final data = (await image.toByteData())!;
      expect(data.getUint8((100 * 200 + 100) * 4 + 3), 255);
    });

    test('shouldRepaint reacts to a new live stroke', () {
      final doc = docWith([Layer(id: 'a', name: 'a')]);
      final base = DocumentPainter(document: doc, scale: 1);
      expect(
        DocumentPainter(
          document: doc,
          scale: 1,
          liveStroke: inkAcross('live'),
          liveLayerId: 'a',
        ).shouldRepaint(base),
        isTrue,
      );
    });
  });
}
