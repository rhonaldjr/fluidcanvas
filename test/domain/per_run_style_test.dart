import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';

TextElement text(String s, {double fontSize = 24}) => TextElement(
  id: 't',
  x: 0,
  y: 0,
  w: 200,
  h: 100,
  fontSize: fontSize,
  runs: [TextRun(s)],
);

void main() {
  group('TextRun per-run overrides', () {
    test('a plain run inherits, overriding nothing', () {
      const run = TextRun('hi');
      expect(run.fontSize, isNull);
      expect(run.colorRGBA, isNull);
      expect(run.isPlain, isTrue);
    });

    test('a size or colour override makes a run non-plain', () {
      expect(const TextRun('hi', fontSize: 40).isPlain, isFalse);
      expect(const TextRun('hi', colorRGBA: 0xFF0000FF).isPlain, isFalse);
    });

    test('the flag byte marks presence, bits 3 and 4', () {
      expect(const TextRun('x').styleFlags & 0x18, 0);
      expect(const TextRun('x', fontSize: 10).styleFlags & 0x8, 0x8);
      expect(const TextRun('x', colorRGBA: 1).styleFlags & 0x10, 0x10);
    });

    test('two runs of different size are not the same style', () {
      const a = TextRun('a', fontSize: 10);
      const b = TextRun('b', fontSize: 20);
      expect(a.sameStyleAs(b), isFalse);
    });

    test('runs merge only when size and colour match too', () {
      final merged = TextElement.normalizeRuns(const [
        TextRun('a', fontSize: 10),
        TextRun('b', fontSize: 10),
        TextRun('c', fontSize: 20),
      ]);
      expect(merged.map((r) => r.text), ['ab', 'c']);
    });

    test('copyWith can clear an override back to inherit', () {
      const run = TextRun('x', fontSize: 40, colorRGBA: 0xFF);
      expect(run.copyWith(clearFontSize: true).fontSize, isNull);
      expect(run.copyWith(clearColor: true).colorRGBA, isNull);
      // Clearing one leaves the other alone.
      expect(run.copyWith(clearFontSize: true).colorRGBA, 0xFF);
    });

    test('a zero or negative run size is a bug', () {
      expect(() => TextRun('x', fontSize: 0), throwsA(isA<AssertionError>()));
    });

    test('equality and hashCode include size and colour', () {
      expect(
        const TextRun('x', fontSize: 10),
        const TextRun('x', fontSize: 10),
      );
      expect(
        const TextRun('x', fontSize: 10),
        isNot(const TextRun('x', fontSize: 11)),
      );
      expect(
        const TextRun('x', fontSize: 10).hashCode,
        const TextRun('x', fontSize: 10).hashCode,
      );
    });
  });

  group('runsWithFontSize', () {
    test('sets a size on a sub-range, splitting the run', () {
      final runs = text('abcdef').runsWithFontSize(2, 4, 40);
      expect(runs.map((r) => r.text), ['ab', 'cd', 'ef']);
      expect(runs[1].fontSize, 40);
      expect(runs[0].fontSize, isNull);
      expect(runs[2].fontSize, isNull);
    });

    test('null clears the override on the range', () {
      final sized = TextElement(
        id: 't',
        x: 0,
        y: 0,
        w: 100,
        h: 40,
        runs: const [TextRun('abcdef', fontSize: 40)],
      );
      final runs = sized.runsWithFontSize(2, 4, null);
      expect(runs.map((r) => r.text), ['ab', 'cd', 'ef']);
      expect(runs[1].fontSize, isNull);
      expect(runs[0].fontSize, 40);
    });

    test('setting then clearing the same range restores the run list', () {
      final original = text('abcdef');
      final sized = original.copyWith(
        runs: original.runsWithFontSize(2, 4, 40),
      );
      final restored = sized.runsWithFontSize(2, 4, null);
      expect(restored, original.runs);
    });
  });

  group('runsWithColor', () {
    test('sets a colour on a sub-range', () {
      final runs = text('abcdef').runsWithColor(0, 3, 0xFF0000FF);
      expect(runs.map((r) => r.text), ['abc', 'def']);
      expect(runs[0].colorRGBA, 0xFF0000FF);
      expect(runs[1].colorRGBA, isNull);
    });
  });

  group('scaling keeps per-run sizes proportional', () {
    test('a corner-resize scales run overrides with the base', () {
      final t = TextElement(
        id: 't',
        x: 0,
        y: 0,
        w: 100,
        h: 40,
        fontSize: 20,
        runs: const [TextRun('big', fontSize: 40), TextRun('small')],
      );
      final scaled = t.scaled(2);
      expect(scaled.fontSize, 40);
      expect(scaled.runs.first.fontSize, 80);
      expect(scaled.runs.last.fontSize, isNull, reason: 'inheriting run stays');
    });
  });
}
