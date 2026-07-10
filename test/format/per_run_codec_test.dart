import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/format/format.dart';

TextElement textOf(List<TextRun> runs) =>
    TextElement(id: 't', x: 0, y: 0, w: 100, h: 40, fontSize: 24, runs: runs);

TextElement roundTrip(TextElement element) =>
    decodeElements(encodeElements([element]), idFor: () => 't').single
        as TextElement;

void main() {
  group('v3 per-run size and colour', () {
    test('a run with a size override round-trips', () {
      final back = roundTrip(textOf(const [TextRun('big', fontSize: 48)]));
      expect(back.runs.single.fontSize, 48);
    });

    test('a run with a colour override round-trips', () {
      final back = roundTrip(
        textOf(const [TextRun('red', colorRGBA: 0xFF0000FF)]),
      );
      expect(back.runs.single.colorRGBA, 0xFF0000FF);
    });

    test('mixed runs, some overriding and some not, survive in order', () {
      final back = roundTrip(
        textOf(const [
          TextRun('plain'),
          TextRun('big', fontSize: 40),
          TextRun('redbig', fontSize: 40, colorRGBA: 0x00FF00FF, bold: true),
        ]),
      );
      expect(back.runs.map((r) => r.text), ['plain', 'big', 'redbig']);
      expect(back.runs[0].fontSize, isNull);
      expect(back.runs[1].fontSize, 40);
      expect(back.runs[2].fontSize, 40);
      expect(back.runs[2].colorRGBA, 0x00FF00FF);
      expect(back.runs[2].bold, isTrue);
    });

    test('the format version is 3', () {
      expect(kSkdFormatVersion, 3);
    });

    test('a run body without overrides is the same length as before', () {
      // A plain run must not have grown: bits 3/4 clear means no extra bytes.
      final plain = encodeElements([
        textOf(const [TextRun('hello')]),
      ]);
      final sized = encodeElements([
        textOf(const [TextRun('hello', fontSize: 9)]),
      ]);
      // The sized one carries exactly four extra bytes (one f32).
      expect(sized.length - plain.length, 4);
    });

    test('a corrupt run size is rejected', () {
      final bytes = encodeElements([
        textOf(const [TextRun('x', fontSize: 10)]),
      ]);
      // Find the fontSize float and zero it. Rather than compute the offset,
      // rely on the reader validating it — feed a zero size via a crafted run.
      // Simpler: a zero override cannot be constructed by the model, and the
      // reader calls _positive, so any zero in that slot throws. We assert the
      // reader path here by mutating the last f32 before the text.
      final view = bytes.buffer.asByteData();
      // Scan for the value 10.0 as a float32 and overwrite with 0.
      for (var i = 0; i + 4 <= bytes.length; i++) {
        if (view.getFloat32(i, Endian.little) == 10.0) {
          view.setFloat32(i, 0, Endian.little);
          break;
        }
      }
      expect(() => decodeElements(bytes), throwsA(isA<SkdFormatException>()));
    });
  });
}
