import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/text_layout.dart';

/// Rendering depends on the machine's fonts, so these assert *layout
/// invariants* — never pixels, never exact heights.
TextElement box({
  double w = 200,
  double h = 100,
  double fontSize = 20,
  String text = 'the quick brown fox jumps over the lazy dog',
}) => TextElement.plain(
  id: 't',
  x: 0,
  y: 0,
  w: w,
  h: h,
  fontSize: fontSize,
  text: text,
);

void main() {
  group('wrapping', () {
    test('a narrower box wraps to more lines, so it is taller', () {
      final wide = layoutText(box(w: 400, h: 400));
      final narrow = layoutText(box(w: 120, h: 400));
      expect(narrow.height, greaterThan(wide.height));
    });

    test('an empty element needs no shrinking', () {
      final layout = layoutText(box(text: '', h: 10));
      expect(layout.fitScale, 1);
      expect(layout.overflows, isFalse);
    });
  });

  group('shrink to fit', () {
    test('text that already fits is not shrunk', () {
      final layout = layoutText(box(h: 400));
      expect(layout.fitScale, 1);
      expect(layout.overflows, isFalse);
    });

    test('text too tall is shrunk until it fits', () {
      final layout = layoutText(box(w: 100, h: 40));
      expect(layout.fitScale, lessThan(1));
      expect(layout.height, lessThanOrEqualTo(40));
      expect(layout.overflows, isFalse);
    });

    test('the scale is monotonic in box height', () {
      final small = layoutText(box(w: 100, h: 40)).fitScale;
      final medium = layoutText(box(w: 100, h: 70)).fitScale;
      final large = layoutText(box(w: 100, h: 300)).fitScale;
      expect(small, lessThanOrEqualTo(medium));
      expect(medium, lessThanOrEqualTo(large));
    });

    test('a wider box needs less shrinking', () {
      final narrow = layoutText(box(w: 80, h: 50)).fitScale;
      final wide = layoutText(box(w: 300, h: 50)).fitScale;
      expect(wide, greaterThanOrEqualTo(narrow));
    });

    test('it never shrinks below the floor, and says it overflows', () {
      final layout = layoutText(
        box(
          w: 60,
          h: 12,
          fontSize: 40,
          text: 'a very long sentence that cannot possibly fit in a tiny box',
        ),
      );
      expect(layout.fitScale, kMinTextFitScale);
      expect(layout.overflows, isTrue);
    });

    test('the fit scale is derived, so it never disagrees with the text', () {
      // Same element laid out twice gives the same answer: the search is
      // deterministic, not "whatever converged".
      final a = layoutText(box(w: 100, h: 45)).fitScale;
      final b = layoutText(box(w: 100, h: 45)).fitScale;
      expect(a, b);
    });

    test('a bigger font in the same box shrinks more', () {
      final small = layoutText(box(w: 150, h: 50, fontSize: 14)).fitScale;
      final big = layoutText(box(w: 150, h: 50, fontSize: 40)).fitScale;
      expect(big, lessThanOrEqualTo(small));
    });
  });

  group('alignment', () {
    test('maps onto Flutter', () {
      expect(flutterAlign(TextAlignment.left), TextAlign.left);
      expect(flutterAlign(TextAlignment.center), TextAlign.center);
      expect(flutterAlign(TextAlignment.right), TextAlign.right);
    });
  });

  group('run styles', () {
    test('bold, italic and underline reach the TextStyle', () {
      final style = runStyle(
        const TextRun('x', bold: true, italic: true, underline: true),
        fontSize: 12,
        fontFamily: '',
        color: const Color(0xFF000000),
      );
      expect(style.fontWeight, FontWeight.bold);
      expect(style.fontStyle, FontStyle.italic);
      expect(style.decoration, TextDecoration.underline);
    });

    test('an empty family means the platform default', () {
      expect(
        runStyle(
          const TextRun('x'),
          fontSize: 12,
          fontFamily: '',
          color: const Color(0xFF000000),
        ).fontFamily,
        isNull,
      );
    });
  });
}
