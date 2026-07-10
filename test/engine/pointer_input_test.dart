import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/engine/pointer_input.dart';

void main() {
  group('normalizePressure', () {
    test('a mouse reports no range and draws at full pressure', () {
      // Flutter gives mice pressure == pressureMin == pressureMax == 1.0.
      expect(normalizePressure(pressure: 1, min: 1, max: 1), 1.0);
    });

    test('a degenerate range never divides by zero', () {
      expect(normalizePressure(pressure: 0.5, min: 0, max: 0), 1.0);
      expect(normalizePressure(pressure: 0.5, min: 2, max: 1), 1.0);
    });

    test('rescales a stylus range onto 0..1', () {
      expect(normalizePressure(pressure: 0, min: 0, max: 4), 0.0);
      expect(normalizePressure(pressure: 2, min: 0, max: 4), 0.5);
      expect(normalizePressure(pressure: 4, min: 0, max: 4), 1.0);
    });

    test('handles a range that does not start at zero', () {
      expect(normalizePressure(pressure: 15, min: 10, max: 20), 0.5);
    });

    test('clamps readings outside the reported range', () {
      expect(normalizePressure(pressure: -5, min: 0, max: 4), 0.0);
      expect(normalizePressure(pressure: 99, min: 0, max: 4), 1.0);
    });

    test('a non-finite reading falls back to full pressure', () {
      expect(normalizePressure(pressure: double.nan, min: 0, max: 4), 1.0);
      expect(normalizePressure(pressure: double.infinity, min: 0, max: 4), 1.0);
    });

    test('always produces a value StrokePoint will accept', () {
      for (final p in [-1.0, 0.0, 0.3, 1.0, 7.0, double.nan]) {
        final value = normalizePressure(pressure: p, min: 0, max: 1);
        expect(value, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  group('documentPoint', () {
    test('at 100% zoom, screen pixels are document pixels', () {
      final point = documentPoint(
        local: const Offset(10, 20),
        scale: 1,
        pressure: 1,
      );
      expect(point.x, 10);
      expect(point.y, 20);
    });

    test(
      'divides by the scale, so a shrunken page maps to a bigger document',
      () {
        // The page is drawn at half size; a click 100px in is 200 document px in.
        final point = documentPoint(
          local: const Offset(100, 50),
          scale: 0.5,
          pressure: 1,
        );
        expect(point.x, 200);
        expect(point.y, 100);
      },
    );

    test('carries pressure through untouched', () {
      expect(
        documentPoint(local: Offset.zero, scale: 1, pressure: 0.25).pressure,
        0.25,
      );
    });

    test('rejects a zero scale rather than producing infinities', () {
      expect(
        () => documentPoint(local: const Offset(1, 1), scale: 0, pressure: 1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('the page origin is the document origin', () {
      final point = documentPoint(local: Offset.zero, scale: 0.37, pressure: 1);
      expect(point.x, 0);
      expect(point.y, 0);
    });
  });
}
