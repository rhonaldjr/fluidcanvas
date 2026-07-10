import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/thinning.dart';

List<StrokePoint> pointsAt(List<(double, double)> coords) => [
  for (final (x, y) in coords) StrokePoint(x: x, y: y),
];

List<(double, double)> coordsOf(List<StrokePoint> points) => [
  for (final p in points) (p.x, p.y),
];

void main() {
  group('isFarEnough', () {
    const origin = StrokePoint(x: 0, y: 0);

    test('a coincident point is never far enough', () {
      expect(isFarEnough(origin, origin), isFalse);
    });

    test('exactly the threshold counts as far enough', () {
      expect(isFarEnough(origin, const StrokePoint(x: 1.5, y: 0)), isTrue);
    });

    test('just under the threshold is rejected', () {
      expect(isFarEnough(origin, const StrokePoint(x: 1.49, y: 0)), isFalse);
    });

    test('measures diagonally, not per axis', () {
      // dx = dy = 1.2, so each axis is under 1.5 but the distance is ~1.70.
      const diagonal = StrokePoint(x: 1.2, y: 1.2);
      expect(diagonal.x, lessThan(kMinPointDistance));
      expect(isFarEnough(origin, diagonal), isTrue);
    });

    test('is symmetric', () {
      const far = StrokePoint(x: 5, y: 5);
      expect(isFarEnough(origin, far), isFarEnough(far, origin));
    });

    test('ignores pressure', () {
      const same = StrokePoint(x: 0, y: 0, pressure: 0.1);
      expect(isFarEnough(origin, same), isFalse);
    });

    test('honours a custom threshold', () {
      const p = StrokePoint(x: 3, y: 0);
      expect(isFarEnough(origin, p, minDistance: 10), isFalse);
      expect(isFarEnough(origin, p, minDistance: 1), isTrue);
    });

    test('a zero threshold keeps everything except an exact repeat', () {
      expect(isFarEnough(origin, origin, minDistance: 0), isTrue);
    });

    test('rejects a negative threshold', () {
      expect(
        () => isFarEnough(origin, origin, minDistance: -1),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('thinPoints', () {
    test('an empty list stays empty', () {
      expect(thinPoints(const []), isEmpty);
    });

    test('a single point is kept', () {
      expect(coordsOf(thinPoints(pointsAt([(1, 2)]))), [(1.0, 2.0)]);
    });

    test('always keeps the first point', () {
      final thinned = thinPoints(pointsAt([(0, 0), (0.1, 0), (0.2, 0)]));
      expect(coordsOf(thinned), [(0.0, 0.0)]);
    });

    test('drops points closer than the threshold', () {
      final thinned = thinPoints(
        pointsAt([(0, 0), (0.5, 0), (1.0, 0), (2.0, 0)]),
      );
      expect(coordsOf(thinned), [(0.0, 0.0), (2.0, 0.0)]);
    });

    test('keeps points at or beyond the threshold', () {
      final thinned = thinPoints(pointsAt([(0, 0), (1.5, 0), (3.0, 0)]));
      expect(thinned, hasLength(3));
    });

    test('measures from the last kept point, not the previous input', () {
      // Ten steps of 1.0 each: measuring against the previous *input* would
      // drop them all, so the stroke would never advance. Measuring against the
      // last kept point keeps every second one.
      final input = pointsAt([for (var i = 0; i <= 10; i++) (i * 1.0, 0.0)]);
      final thinned = thinPoints(input);

      expect(thinned.length, greaterThan(2));
      expect(coordsOf(thinned).take(3), [(0.0, 0.0), (2.0, 0.0), (4.0, 0.0)]);
    });

    test('never drops below two points for a long drag', () {
      final input = pointsAt([for (var i = 0; i < 100; i++) (i * 10.0, 0.0)]);
      expect(thinPoints(input), hasLength(100));
    });

    test('collapses a jitter cloud to one point', () {
      final input = pointsAt([
        (0, 0),
        (0.1, 0.1),
        (-0.1, 0.05),
        (0.05, -0.1),
        (0, 0.2),
      ]);
      expect(thinPoints(input), hasLength(1));
    });

    test('preserves order and identity of kept points', () {
      final input = pointsAt([(0, 0), (0.1, 0), (10, 0), (10.1, 0), (20, 0)]);
      final thinned = thinPoints(input);
      expect(coordsOf(thinned), [(0.0, 0.0), (10.0, 0.0), (20.0, 0.0)]);
    });

    test('keeps pressure on the points it keeps', () {
      final input = [
        const StrokePoint(x: 0, y: 0, pressure: 0.2),
        const StrokePoint(x: 10, y: 0, pressure: 0.8),
      ];
      expect([for (final p in thinPoints(input)) p.pressure], [0.2, 0.8]);
    });

    test('does not mutate the input list', () {
      final input = pointsAt([(0, 0), (0.1, 0)]);
      thinPoints(input);
      expect(input, hasLength(2));
    });

    test('is idempotent', () {
      final once = thinPoints(pointsAt([(0, 0), (0.5, 0), (2, 0), (2.5, 0)]));
      expect(thinPoints(once), once);
    });

    test('a larger threshold thins more aggressively', () {
      final input = pointsAt([for (var i = 0; i <= 20; i++) (i * 1.0, 0.0)]);
      final coarse = thinPoints(input, minDistance: 10);
      final fine = thinPoints(input, minDistance: 2);
      expect(coarse.length, lessThan(fine.length));
    });
  });

  group('distanceBetween', () {
    test('computes euclidean distance', () {
      expect(
        distanceBetween(
          const StrokePoint(x: 0, y: 0),
          const StrokePoint(x: 3, y: 4),
        ),
        closeTo(5, 1e-9),
      );
    });

    test('is zero for coincident points', () {
      const p = StrokePoint(x: 7, y: 9);
      expect(distanceBetween(p, p), 0);
    });

    test('agrees with isFarEnough at the threshold', () {
      const a = StrokePoint(x: 0, y: 0);
      const b = StrokePoint(x: 1.5, y: 0);
      expect(distanceBetween(a, b), closeTo(kMinPointDistance, 1e-9));
      expect(isFarEnough(a, b), isTrue);
    });
  });
}
