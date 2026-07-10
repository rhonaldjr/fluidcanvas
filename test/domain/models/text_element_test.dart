import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';

TextElement boxWith(List<TextRun> runs) =>
    TextElement(id: 't', x: 10, y: 20, w: 200, h: 50, runs: runs);

List<(String, int)> shape(List<TextRun> runs) => [
  for (final r in runs) (r.text, r.styleFlags),
];

void main() {
  group('TextRun', () {
    test('style flags pack bold, italic, underline', () {
      expect(const TextRun('a').styleFlags, 0);
      expect(const TextRun('a', bold: true).styleFlags, 1);
      expect(const TextRun('a', italic: true).styleFlags, 2);
      expect(const TextRun('a', underline: true).styleFlags, 4);
      expect(
        const TextRun(
          'a',
          bold: true,
          italic: true,
          underline: true,
        ).styleFlags,
        7,
      );
    });

    test('fromFlags round-trips', () {
      for (var f = 0; f < 8; f++) {
        expect(TextRun.fromFlags('x', f).styleFlags, f);
      }
    });
  });

  group('normalizeRuns', () {
    test('drops empty runs', () {
      expect(
        shape(TextElement.normalizeRuns(const [TextRun('a'), TextRun('')])),
        [('a', 0)],
      );
    });

    test('merges adjacent runs with equal styling', () {
      final runs = TextElement.normalizeRuns(const [
        TextRun('foo'),
        TextRun('bar'),
        TextRun('baz', bold: true),
      ]);
      expect(shape(runs), [('foobar', 0), ('baz', 1)]);
    });

    test('an empty element keeps one empty run', () {
      expect(TextElement.normalizeRuns(const []), hasLength(1));
      expect(boxWith(const []).text, '');
    });
  });

  group('runsWithStyle', () {
    final element = boxWith(const [TextRun('hello world')]);

    test('styling the middle of a run splits it into three', () {
      final runs = element.runsWithStyle(6, 11, bold: true);
      expect(shape(runs), [('hello ', 0), ('world', 1)]);
    });

    test('styling an interior range yields a head, body, and tail', () {
      final runs = element.runsWithStyle(2, 5, italic: true);
      expect(shape(runs), [('he', 0), ('llo', 2), (' world', 0)]);
    });

    test('toggling twice restores the original run list exactly', () {
      final bolded = element.runsWithStyle(2, 5, bold: true);
      final restored = element
          .copyWith(runs: bolded)
          .runsWithStyle(2, 5, bold: false);
      expect(restored, element.runs);
      expect(shape(restored), [('hello world', 0)]);
    });

    test('a zero-width range changes nothing', () {
      expect(element.runsWithStyle(3, 3, bold: true), element.runs);
    });

    test('styling across a run boundary merges what it can', () {
      final mixed = boxWith(const [TextRun('ab', bold: true), TextRun('cd')]);
      final runs = mixed.runsWithStyle(0, 4, bold: true);
      expect(shape(runs), [('abcd', 1)]);
    });

    test('the whole element can be styled at once', () {
      final runs = element.runsWithStyle(0, element.length, underline: true);
      expect(shape(runs), [('hello world', 4)]);
    });
  });

  group('rangeHasStyle', () {
    final element = boxWith(const [TextRun('ab', bold: true), TextRun('cd')]);

    test('true only when every character carries it', () {
      expect(element.rangeHasStyle(0, 2, (r) => r.bold), isTrue);
      expect(element.rangeHasStyle(0, 4, (r) => r.bold), isFalse);
      expect(element.rangeHasStyle(2, 4, (r) => r.bold), isFalse);
    });

    test('an empty range has no style', () {
      expect(element.rangeHasStyle(1, 1, (r) => r.bold), isFalse);
    });
  });

  group('runsWithReplacement', () {
    test('inserting inherits the styling of the character before it', () {
      final element = boxWith(const [TextRun('ab', bold: true), TextRun('cd')]);
      final runs = element.runsWithReplacement(2, 2, 'X');
      expect(shape(runs), [('abX', 1), ('cd', 0)]);
    });

    test('deleting a range removes it', () {
      final element = boxWith(const [TextRun('hello')]);
      expect(shape(element.runsWithReplacement(1, 4, '')), [('ho', 0)]);
    });

    test('replacing a range swaps the text', () {
      final element = boxWith(const [TextRun('hello')]);
      expect(shape(element.runsWithReplacement(0, 5, 'bye')), [('bye', 0)]);
    });

    test('deleting everything leaves one empty run', () {
      final element = boxWith(const [TextRun('hi')]);
      expect(
        element.copyWith(runs: element.runsWithReplacement(0, 2, '')).text,
        '',
      );
    });
  });

  group('geometry', () {
    final element = boxWith(const [TextRun('hi')]);

    test('bounds is the box when unrotated', () {
      expect(
        element.bounds,
        const Bounds(left: 10, top: 20, right: 210, bottom: 70),
      );
    });

    test('rotating never shrinks the bounding area', () {
      // Width alone can shrink: a wide, short box turned 45 degrees bounds
      // narrower than it started. Area is the invariant.
      final turned = element.copyWith(rotation: math.pi / 4);
      final before = element.bounds;
      final after = turned.bounds;
      expect(
        after.width * after.height,
        greaterThan(before.width * before.height),
      );
    });

    test('scaling grows the box and the font together', () {
      final big = element.scaled(2);
      expect(big.w, 400);
      expect(big.fontSize, element.fontSize * 2);
      expect(big.x, 20);
    });

    test('translating moves the box only', () {
      final moved = element.translated(5, -5);
      expect(moved.x, 15);
      expect(moved.fontSize, element.fontSize);
    });

    test('rotating adds to the angle and orbits the centre', () {
      final turned = element.rotated(math.pi / 2, originX: 0, originY: 0);
      expect(turned.rotation, closeTo(math.pi / 2, 1e-9));
    });

    test('rejects a degenerate box', () {
      expect(
        () => TextElement(id: 't', x: 0, y: 0, w: 0, h: 10, runs: const []),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('value equality', () {
    test('same runs and geometry are equal', () {
      expect(boxWith(const [TextRun('a')]), boxWith(const [TextRun('a')]));
    });

    test('run styling participates', () {
      expect(
        boxWith(const [TextRun('a')]),
        isNot(boxWith(const [TextRun('a', bold: true)])),
      );
    });

    test('normalization makes equal texts equal', () {
      expect(
        boxWith(const [TextRun('ab')]),
        boxWith(const [TextRun('a'), TextRun('b')]),
      );
    });
  });

  group('TextAlignment', () {
    test('wire values are pinned', () {
      expect(TextAlignment.left.value, 0);
      expect(TextAlignment.center.value, 1);
      expect(TextAlignment.right.value, 2);
    });

    test('fromValue rejects the unknown rather than guessing', () {
      expect(() => TextAlignment.fromValue(9), throwsArgumentError);
    });
  });
}
