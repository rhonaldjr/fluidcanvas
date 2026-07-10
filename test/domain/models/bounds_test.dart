import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';

void main() {
  group('construction', () {
    test('exposes width, height, and center', () {
      const b = Bounds(left: 10, top: 20, right: 40, bottom: 60);
      expect(b.width, 30);
      expect(b.height, 40);
      expect(b.centerX, 25);
      expect(b.centerY, 40);
    });

    test('fromLTWH matches an equivalent LTRB', () {
      expect(
        Bounds.fromLTWH(10, 20, 30, 40),
        const Bounds(left: 10, top: 20, right: 40, bottom: 60),
      );
    });

    test('Bounds.point is zero-size', () {
      const b = Bounds.point(5, 7);
      expect(b.width, 0);
      expect(b.height, 0);
      expect(b.isDegenerate, isTrue);
    });

    test('rejects inverted rectangles', () {
      expect(
        () => Bounds(left: 10, top: 0, right: 5, bottom: 10),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => Bounds(left: 0, top: 10, right: 10, bottom: 5),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects negative extents in fromLTWH', () {
      expect(
        () => Bounds.fromLTWH(0, 0, -1, 10),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  test('isDegenerate is true for a zero-width line, false for an area', () {
    expect(
      const Bounds(left: 5, top: 0, right: 5, bottom: 10).isDegenerate,
      isTrue,
    );
    expect(
      const Bounds(left: 0, top: 0, right: 1, bottom: 1).isDegenerate,
      isFalse,
    );
  });

  group('union', () {
    test('grows to contain both rectangles', () {
      const a = Bounds(left: 0, top: 0, right: 10, bottom: 10);
      const b = Bounds(left: 5, top: -5, right: 20, bottom: 8);
      expect(a.union(b), const Bounds(left: 0, top: -5, right: 20, bottom: 10));
    });

    test('is a no-op when one contains the other', () {
      const outer = Bounds(left: 0, top: 0, right: 10, bottom: 10);
      const inner = Bounds(left: 2, top: 2, right: 3, bottom: 3);
      expect(outer.union(inner), outer);
      expect(inner.union(outer), outer);
    });
  });

  group('inflate', () {
    test('grows every side', () {
      const b = Bounds(left: 10, top: 10, right: 20, bottom: 20);
      expect(
        b.inflate(5),
        const Bounds(left: 5, top: 5, right: 25, bottom: 25),
      );
    });

    test('a negative amount shrinks', () {
      const b = Bounds(left: 0, top: 0, right: 20, bottom: 20);
      expect(
        b.inflate(-5),
        const Bounds(left: 5, top: 5, right: 15, bottom: 15),
      );
    });

    test('shrinking past zero is rejected rather than inverting', () {
      const b = Bounds(left: 0, top: 0, right: 4, bottom: 4);
      expect(() => b.inflate(-5), throwsA(isA<AssertionError>()));
    });
  });

  group('value equality', () {
    test('equal rectangles are equal and share a hashCode', () {
      const a = Bounds(left: 1, top: 2, right: 3, bottom: 4);
      const b = Bounds(left: 1, top: 2, right: 3, bottom: 4);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differing rectangles are unequal', () {
      const a = Bounds(left: 1, top: 2, right: 3, bottom: 4);
      expect(a, isNot(const Bounds(left: 1, top: 2, right: 3, bottom: 5)));
    });
  });
}
