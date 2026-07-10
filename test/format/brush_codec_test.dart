import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/format/format.dart';

Stroke strokeOf(int toolId) => Stroke(
  id: 's',
  colorRGBA: 0x12345678,
  baseWidth: 5,
  toolId: toolId,
  points: const [
    StrokePoint(x: 1, y: 2, pressure: 0.5),
    StrokePoint(x: 3, y: 4, pressure: 1),
  ],
);

Stroke roundTrip(Stroke stroke) =>
    decodeElements(encodeElements([stroke]), idFor: () => 's').single as Stroke;

void main() {
  group('brush engines round-trip without a format bump', () {
    for (final (name, toolId) in [
      ('pen', ToolId.pen),
      ('eraser', ToolId.eraser),
      ('pencil', ToolId.pencil),
      ('airbrush', ToolId.airbrush),
      ('texture', ToolId.texture),
    ]) {
      test('$name survives a round trip', () {
        expect(roundTrip(strokeOf(toolId)).toolId, toolId);
      });
    }

    test('a new brush changes no bytes but the toolId', () {
      // Brushes added no structure: a pencil stroke and a pen stroke of the
      // same geometry encode to identical blobs apart from the one toolId byte.
      final pen = encodeElements([strokeOf(ToolId.pen)]);
      final pencil = encodeElements([strokeOf(ToolId.pencil)]);
      expect(pencil.length, pen.length);
      final diff = [
        for (var i = 0; i < pen.length; i++)
          if (pen[i] != pencil[i]) i,
      ];
      expect(diff, hasLength(1), reason: 'only the toolId byte differs');
    });
  });

  group('forward compatibility', () {
    test('a brush id this build does not know is kept, not rejected', () {
      // A future build might write toolId 99. An older reader must tolerate it
      // and fall back to the pen, exactly as the spec promises.
      final bytes = encodeElements([strokeOf(ToolId.pen)]);
      final corrupt = Uint8List.fromList(bytes);
      // toolId sits after: magic u32, count u32, type u8 + reserved u8[3],
      // colorRGBA u32, baseWidth f32 = offset 20.
      corrupt[20] = 99;

      final stroke = decodeElements(corrupt, idFor: () => 's').single as Stroke;
      expect(stroke.toolId, 99);
      expect(
        stroke.isEraser,
        isFalse,
        reason: 'unknown brush is not an eraser',
      );
    });
  });
}
