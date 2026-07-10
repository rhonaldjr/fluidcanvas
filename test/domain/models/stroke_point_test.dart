import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';

void main() {
  test('pressure defaults to 1.0 for devices that report none', () {
    expect(const StrokePoint(x: 1, y: 2).pressure, 1.0);
  });

  test('rejects pressure outside 0..1', () {
    expect(
      () => StrokePoint(x: 0, y: 0, pressure: -0.1),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => StrokePoint(x: 0, y: 0, pressure: 1.1),
      throwsA(isA<AssertionError>()),
    );
  });

  test('accepts the boundary pressures', () {
    expect(const StrokePoint(x: 0, y: 0, pressure: 0).pressure, 0);
    expect(const StrokePoint(x: 0, y: 0, pressure: 1).pressure, 1);
  });

  group('copyWith', () {
    const original = StrokePoint(x: 1, y: 2, pressure: 0.5);

    test('replaces only the named fields', () {
      expect(
        original.copyWith(x: 9),
        const StrokePoint(x: 9, y: 2, pressure: 0.5),
      );
      expect(
        original.copyWith(pressure: 0),
        const StrokePoint(x: 1, y: 2, pressure: 0),
      );
    });

    test('with no arguments returns an equal point', () {
      expect(original.copyWith(), original);
    });
  });

  group('value equality', () {
    test('same coordinates and pressure are equal', () {
      const a = StrokePoint(x: 1, y: 2, pressure: 0.5);
      const b = StrokePoint(x: 1, y: 2, pressure: 0.5);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('pressure participates in equality', () {
      expect(
        const StrokePoint(x: 1, y: 2, pressure: 0.5),
        isNot(const StrokePoint(x: 1, y: 2, pressure: 0.6)),
      );
    });
  });
}
