import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/format/format.dart';

/// Ids are not persisted, so a round-trip must mint them. A counter keeps the
/// comparison deterministic.
String Function() counter() {
  var n = 0;
  return () => 'e${n++}';
}

/// Every float is stored as f32, so only f32-representable values survive a
/// round-trip exactly. These all are.
Stroke stroke({int toolId = ToolId.pen}) => Stroke(
  id: 'e0',
  colorRGBA: 0x1B1B1FFF,
  baseWidth: 4.5,
  toolId: toolId,
  points: const [
    StrokePoint(x: 1.5, y: -2.25, pressure: 0.5),
    StrokePoint(x: 100, y: 50.75, pressure: 1),
  ],
);

Shape shape(ShapeType type) => Shape(
  id: 'e0',
  type: type,
  x: 10.5,
  y: 20.25,
  w: 100,
  h: 60.5,
  rotation: 0.5,
  strokeColorRGBA: 0xFF0000FF,
  fillColorRGBA: 0x00FF00FF,
  strokeWidth: 2.5,
  strokeStyle: StrokeStyle.dashed,
);

TextElement text() => TextElement(
  id: 'e0',
  x: 5,
  y: 6,
  w: 200,
  h: 80.5,
  rotation: -0.25,
  fontFamily: 'Helvetica',
  fontSize: 18,
  colorRGBA: 0x112233FF,
  align: TextAlignment.center,
  runs: const [
    TextRun('plain '),
    TextRun('bold', bold: true),
    TextRun(' ünïcødé 😀', italic: true, underline: true),
  ],
);

List<CanvasElement> roundTrip(List<CanvasElement> elements) =>
    decodeElements(encodeElements(elements), idFor: counter());

void main() {
  group('header', () {
    test('starts with the SKD1 magic and a count', () {
      final bytes = encodeElements([stroke()]);
      final data = ByteData.view(bytes.buffer);
      expect(data.getUint32(0, Endian.little), kElementBlobMagic);
      expect(data.getUint32(4, Endian.little), 1);
    });

    test('an empty layer encodes to just a header', () {
      expect(encodeElements(const []), hasLength(8));
      expect(decodeElements(encodeElements(const [])), isEmpty);
    });
  });

  group('round trip', () {
    test('a pen stroke survives exactly', () {
      expect(roundTrip([stroke()]).single, stroke());
    });

    test('an eraser stroke keeps its toolId', () {
      final decoded =
          roundTrip([stroke(toolId: ToolId.eraser)]).single as Stroke;
      expect(decoded.isEraser, isTrue);
    });

    test('every shape type survives exactly', () {
      for (final type in ShapeType.values) {
        expect(roundTrip([shape(type)]).single, shape(type), reason: type.name);
      }
    });

    test('text with mixed runs and non-ASCII survives exactly', () {
      expect(roundTrip([text()]).single, text());
    });

    test('a mixed layer keeps its z-order', () {
      final elements = [stroke(), shape(ShapeType.arrow), text()];
      final decoded = roundTrip(elements);
      expect(decoded[0], isA<Stroke>());
      expect(decoded[1], isA<Shape>());
      expect(decoded[2], isA<TextElement>());
    });

    test('ids are regenerated, not persisted', () {
      final decoded = decodeElements(
        encodeElements([stroke(), shape(ShapeType.line)]),
        idFor: counter(),
      );
      expect([for (final e in decoded) e.id], ['e0', 'e1']);
    });

    test('a shape is normalized on write', () {
      final flipped = shape(
        ShapeType.rectangle,
      ).copyWith(x: 110.5, y: 80.75, w: -100, h: -60.5);
      final decoded = roundTrip([flipped]).single as Shape;
      expect(decoded.w, 100);
      expect(decoded.x, 10.5);
    });

    test('an empty text element survives', () {
      final empty = TextElement.plain(id: 'e0', x: 0, y: 0, w: 10, h: 10);
      expect(roundTrip([empty]).single, empty);
    });
  });

  group('rejection', () {
    test('bad magic', () {
      final bytes = encodeElements([stroke()]);
      bytes[0] = 0xFF;
      expect(
        () => decodeElements(bytes),
        throwsA(
          isA<SkdFormatException>().having(
            (e) => e.reason,
            'reason',
            contains('magic'),
          ),
        ),
      );
    });

    test('truncated data', () {
      final bytes = encodeElements([stroke()]);
      expect(
        () => decodeElements(bytes.sublist(0, bytes.length - 6)),
        throwsA(
          isA<SkdFormatException>().having(
            (e) => e.reason,
            'reason',
            contains('truncated'),
          ),
        ),
      );
    });

    test('trailing bytes', () {
      final bytes = encodeElements([stroke()]);
      final padded = Uint8List(bytes.length + 4)..setAll(0, bytes);
      expect(
        () => decodeElements(padded),
        throwsA(
          isA<SkdFormatException>().having(
            (e) => e.reason,
            'reason',
            contains('trailing'),
          ),
        ),
      );
    });

    test('an unknown elementType is rejected, not skipped', () {
      // Bodies are variable-length, so skipping is impossible.
      final bytes = encodeElements([stroke()]);
      bytes[8] = 99;
      expect(
        () => decodeElements(bytes),
        throwsA(
          isA<SkdFormatException>().having(
            (e) => e.reason,
            'reason',
            contains('unknown elementType 99'),
          ),
        ),
      );
    });

    test('an unknown shapeType is rejected', () {
      final bytes = encodeElements([shape(ShapeType.rectangle)]);
      bytes[12] = 42; // shapeType byte
      expect(() => decodeElements(bytes), throwsA(isA<SkdFormatException>()));
    });

    test('a zero stroke width is rejected rather than asserted on', () {
      final bytes = encodeElements([stroke()]);
      // baseWidth is the f32 at offset 16 (8 header + 4 type + 4 colour).
      ByteData.view(bytes.buffer).setFloat32(16, 0, Endian.little);
      expect(
        () => decodeElements(bytes),
        throwsA(
          isA<SkdFormatException>().having(
            (e) => e.reason,
            'reason',
            contains('positive'),
          ),
        ),
      );
    });

    test(
      'a header claiming more elements than exist is truncated, not silent',
      () {
        final bytes = encodeElements([stroke()]);
        ByteData.view(bytes.buffer).setUint32(4, 5, Endian.little);
        expect(() => decodeElements(bytes), throwsA(isA<SkdFormatException>()));
      },
    );
  });
}
