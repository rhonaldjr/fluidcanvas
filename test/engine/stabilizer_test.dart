import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/stabilizer.dart';
import 'package:inkpad/engine/thinning.dart';

List<StrokePoint> pointsAt(List<(double, double)> coords) => [
  for (final (x, y) in coords) StrokePoint(x: x, y: y),
];

void main() {
  group('construction', () {
    test('defaults to off', () {
      final s = Stabilizer();
      expect(s.strength, 0);
      expect(s.isEnabled, isFalse);
      expect(s.radius, 0);
    });

    test('radius grows with strength', () {
      expect(Stabilizer(strength: 1).radius, kStabilizerRadiusPerUnit);
      expect(
        Stabilizer(strength: kMaxStabilizerStrength).radius,
        kMaxStabilizerStrength * kStabilizerRadiusPerUnit,
      );
    });

    test('rejects a strength outside 0..10', () {
      expect(() => Stabilizer(strength: -1), throwsA(isA<AssertionError>()));
      expect(() => Stabilizer(strength: 11), throwsA(isA<AssertionError>()));
    });
  });

  group('strength 0 is a pass-through', () {
    test('every point comes back unchanged', () {
      final input = pointsAt([(0, 0), (0.1, 0), (5, 5), (100, 3)]);
      expect(stabilizePoints(input), input);
    });

    test('finish adds nothing', () {
      final s = Stabilizer()..process(const StrokePoint(x: 1, y: 1));
      expect(s.finish(), isNull);
    });

    test('pressure survives', () {
      const p = StrokePoint(x: 1, y: 2, pressure: 0.3);
      expect(Stabilizer().process(p), p);
    });
  });

  group('enabled', () {
    test('the first point anchors and is emitted', () {
      final s = Stabilizer(strength: 5);
      expect(s.process(const StrokePoint(x: 10, y: 10)), isNotNull);
    });

    test('movement inside the radius is slack and emits nothing', () {
      final s =
          Stabilizer(strength: 5) // radius 20
            ..process(const StrokePoint(x: 0, y: 0));

      expect(s.process(const StrokePoint(x: 5, y: 0)), isNull);
      expect(s.process(const StrokePoint(x: 0, y: 19)), isNull);
      expect(s.process(const StrokePoint(x: -19, y: 0)), isNull);
    });

    test('a point exactly at the radius is still slack', () {
      final s =
          Stabilizer(strength: 1) // radius 4
            ..process(const StrokePoint(x: 0, y: 0));
      expect(s.process(const StrokePoint(x: 4, y: 0)), isNull);
    });

    test('beyond the radius the anchor is dragged along', () {
      final s =
          Stabilizer(strength: 1) // radius 4
            ..process(const StrokePoint(x: 0, y: 0));

      final moved = s.process(const StrokePoint(x: 10, y: 0))!;
      // The anchor ends up exactly `radius` behind the pen.
      expect(moved.x, closeTo(6, 1e-9));
      expect(moved.y, closeTo(0, 1e-9));
    });

    test('the anchor always trails the cursor by exactly the radius', () {
      final s = Stabilizer(strength: 3); // radius 12
      s.process(const StrokePoint(x: 0, y: 0));

      for (final raw in pointsAt([(50, 0), (50, 60), (-20, 60), (0, 0)])) {
        final anchor = s.process(raw);
        if (anchor != null) {
          expect(distanceBetween(anchor, raw), closeTo(s.radius, 1e-6));
        }
      }
    });

    test('the emitted point lies on the segment from anchor to cursor', () {
      final s =
          Stabilizer(strength: 2) // radius 8
            ..process(const StrokePoint(x: 0, y: 0));

      final moved = s.process(const StrokePoint(x: 30, y: 40))!; // distance 50
      // t = (50 - 8) / 50 = 0.84
      expect(moved.x, closeTo(30 * 0.84, 1e-9));
      expect(moved.y, closeTo(40 * 0.84, 1e-9));
    });

    test('output never leaves the bounds of the input', () {
      final input = pointsAt([(0, 0), (100, 0), (100, 50), (0, 50)]);
      for (final point in stabilizePoints(input, strength: 4)) {
        expect(point.x, inInclusiveRange(0, 100));
        expect(point.y, inInclusiveRange(0, 50));
      }
    });

    test('carries the cursor pressure onto the anchor', () {
      final s = Stabilizer(strength: 1)
        ..process(const StrokePoint(x: 0, y: 0, pressure: 1));
      final moved = s.process(const StrokePoint(x: 20, y: 0, pressure: 0.25))!;
      expect(moved.pressure, 0.25);
    });

    test('stronger stabilization emits fewer points', () {
      final jitter = pointsAt([
        for (var i = 0; i < 60; i++) (i * 2.0, (i.isEven ? 3.0 : -3.0)),
      ]);
      final light = stabilizePoints(jitter, strength: 1);
      final heavy = stabilizePoints(jitter, strength: 8);
      expect(heavy.length, lessThan(light.length));
    });

    test('tremor in place collapses to a single point plus the tail', () {
      final tremor = pointsAt([(0, 0), (2, 1), (-1, 2), (1, -2), (0, 1)]);
      // radius 20: nothing escapes the string.
      final out = stabilizePoints(tremor, strength: 5);
      expect(out.length, 2); // the anchor, then finish() snapping to the cursor
      expect(out.first.x, 0);
      expect(out.last.x, 0);
      expect(out.last.y, 1);
    });
  });

  group('finish', () {
    test('snaps the stroke to the cursor so it does not end short', () {
      final s = Stabilizer(strength: 5)
        ..process(const StrokePoint(x: 0, y: 0))
        ..process(const StrokePoint(x: 10, y: 0)); // slack, no emit

      final tail = s.finish()!;
      expect(tail.x, 10);
    });

    test('emits nothing when the anchor already sits on the cursor', () {
      final s = Stabilizer(strength: 5)..process(const StrokePoint(x: 3, y: 3));
      expect(s.finish(), isNull);
    });

    test('emits nothing when no point was ever fed', () {
      expect(Stabilizer(strength: 5).finish(), isNull);
    });

    test('a stabilized stroke still starts and ends on the raw endpoints', () {
      final input = pointsAt([(0, 0), (30, 10), (60, -10), (90, 0)]);
      final out = stabilizePoints(input, strength: 3);
      expect(out.first.x, 0);
      expect(out.first.y, 0);
      expect(out.last.x, 90);
      expect(out.last.y, 0);
    });
  });
}
