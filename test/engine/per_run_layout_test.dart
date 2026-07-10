import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/text_layout.dart';

TextElement text(List<TextRun> runs, {double h = 400}) =>
    TextElement(id: 't', x: 0, y: 0, w: 400, h: h, fontSize: 20, runs: runs);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('per-run size reaches layout', () {
    test('a big run makes the paragraph taller than an all-small one', () {
      // Not a pixel assertion: a larger run is simply taller, whatever the font.
      final small = layoutText(text(const [TextRun('one line of text')]));
      final big = layoutText(
        text(const [TextRun('one line of '), TextRun('text', fontSize: 80)]),
      );
      expect(big.height, greaterThan(small.height));
    });

    test('per-run sizes ride the shrink-to-fit scale', () {
      // A big run forces the box to shrink the whole paragraph. That the run
      // participates in the fit is the point — its size is not left at full
      // scale while everything else shrinks around it.
      final layout = layoutText(
        text(const [TextRun('big word', fontSize: 90)], h: 60),
      );
      expect(layout.fitScale, lessThan(1), reason: 'the box had to shrink it');
    });
  });

  group('runStyle applies the override', () {
    test('a run colour overrides the element colour', () {
      final style = runStyle(
        const TextRun('x', colorRGBA: 0xFF0000FF),
        fontSize: 20,
        fontFamily: '',
        color: const Color(0xFF000000),
      );
      expect(style.color, const Color(0xFFFF0000));
    });

    test('an inheriting run keeps the element colour', () {
      final style = runStyle(
        const TextRun('x'),
        fontSize: 20,
        fontFamily: '',
        color: const Color(0xFF123456),
      );
      expect(style.color, const Color(0xFF123456));
    });
  });
}
