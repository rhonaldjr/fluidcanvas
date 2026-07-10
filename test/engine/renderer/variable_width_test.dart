import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/renderer/variable_width.dart';

List<StrokePoint> line(int n, {double pressure = 1.0}) => [
  for (var i = 0; i < n; i++)
    StrokePoint(x: i * 10.0, y: 0, pressure: pressure),
];

void main() {
  group('widthForPressure', () {
    test('full pressure gives the base width', () {
      expect(widthForPressure(10, 1), 10);
    });

    test('zero pressure gives the floor, not zero', () {
      // A stroke that tapers to nothing reads as a dropout.
      expect(widthForPressure(10, 0), 10 * kPressureMinFactor);
      expect(widthForPressure(10, 0), greaterThan(0));
    });

    test('interpolates linearly between the floor and the base width', () {
      final half = widthForPressure(10, 0.5);
      expect(
        half,
        closeTo(
          10 * (kPressureMinFactor + (1 - kPressureMinFactor) * 0.5),
          1e-9,
        ),
      );
      expect(half, greaterThan(widthForPressure(10, 0)));
      expect(half, lessThan(widthForPressure(10, 1)));
    });

    test('is monotonic in pressure', () {
      var previous = 0.0;
      for (var p = 0.0; p <= 1.0; p += 0.1) {
        final width = widthForPressure(8, p);
        expect(width, greaterThan(previous));
        previous = width;
      }
    });

    test('scales with the base width', () {
      expect(
        widthForPressure(20, 0.3),
        closeTo(2 * widthForPressure(10, 0.3), 1e-9),
      );
    });

    test('never exceeds the base width', () {
      for (var p = 0.0; p <= 1.0; p += 0.05) {
        expect(widthForPressure(6, p), lessThanOrEqualTo(6 + 1e-9));
      }
    });

    test('a minFactor of 1 gives a constant width', () {
      expect(widthForPressure(10, 0, minFactor: 1), 10);
      expect(widthForPressure(10, 1, minFactor: 1), 10);
    });

    test('rejects invalid inputs', () {
      expect(() => widthForPressure(0, 1), throwsA(isA<AssertionError>()));
      expect(() => widthForPressure(10, 1.5), throwsA(isA<AssertionError>()));
      expect(
        () => widthForPressure(10, 1, minFactor: 0),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('buildVariableWidthPath', () {
    test('no points yields an empty path', () {
      expect(buildVariableWidthPath(const [], 4).getBounds().isEmpty, isTrue);
    });

    test('one point yields a disc of the pressure width', () {
      final bounds = buildVariableWidthPath([
        const StrokePoint(x: 10, y: 10),
      ], 8).getBounds();

      expect(bounds.width, closeTo(8, 1e-6));
      expect(bounds.height, closeTo(8, 1e-6));
      expect(bounds.center.dx, closeTo(10, 1e-6));
      expect(bounds.center.dy, closeTo(10, 1e-6));
    });

    test('a light single point still leaves a visible mark', () {
      final bounds = buildVariableWidthPath([
        const StrokePoint(x: 0, y: 0, pressure: 0),
      ], 10).getBounds();
      expect(bounds.width, closeTo(10 * kPressureMinFactor, 1e-6));
    });

    test('a straight full-pressure line is baseWidth thick', () {
      final bounds = buildVariableWidthPath(line(5), 6).getBounds();
      expect(bounds.height, closeTo(6, 1e-6));
    });

    test(
      'the path never strays further than half the max width from the centreline',
      () {
        final points = [
          const StrokePoint(x: 0, y: 0, pressure: 0.2),
          const StrokePoint(x: 10, y: 10, pressure: 1.0),
          const StrokePoint(x: 20, y: 0, pressure: 0.5),
        ];
        const baseWidth = 8.0;
        final bounds = buildVariableWidthPath(points, baseWidth).getBounds();

        final stroke = Stroke(
          id: 's',
          colorRGBA: 0,
          baseWidth: baseWidth,
          points: points,
        );
        final allowed = stroke.bounds!.inflate(baseWidth / 2);

        expect(bounds.left, greaterThanOrEqualTo(allowed.left - 1e-6));
        expect(bounds.top, greaterThanOrEqualTo(allowed.top - 1e-6));
        expect(bounds.right, lessThanOrEqualTo(allowed.right + 1e-6));
        expect(bounds.bottom, lessThanOrEqualTo(allowed.bottom + 1e-6));
      },
    );

    test('a light stroke is thinner than a heavy one', () {
      final light = buildVariableWidthPath(
        line(4, pressure: 0.1),
        10,
      ).getBounds();
      final heavy = buildVariableWidthPath(
        line(4, pressure: 1.0),
        10,
      ).getBounds();
      expect(light.height, lessThan(heavy.height));
    });

    test('width tracks pressure along the stroke', () {
      // Thin at the start, thick at the end: the path is wider near the end.
      final points = [
        const StrokePoint(x: 0, y: 0, pressure: 0),
        const StrokePoint(x: 50, y: 0, pressure: 1),
      ];
      final path = buildVariableWidthPath(points, 20);

      // Sample the outline: near x=0 it hugs the axis, near x=50 it spreads.
      expect(path.contains(const Offset(0, 9)), isFalse);
      expect(path.contains(const Offset(50, 9)), isTrue);
    });

    test('coincident points do not produce NaNs', () {
      final points = [
        const StrokePoint(x: 5, y: 5),
        const StrokePoint(x: 5, y: 5),
        const StrokePoint(x: 5, y: 5),
      ];
      final bounds = buildVariableWidthPath(points, 4).getBounds();
      expect(bounds.left.isFinite, isTrue);
      expect(bounds.width.isFinite, isTrue);
    });

    test('a stroke doubling back on itself stays finite', () {
      final points = [
        const StrokePoint(x: 0, y: 0),
        const StrokePoint(x: 10, y: 0),
        const StrokePoint(x: 0, y: 0),
      ];
      expect(
        buildVariableWidthPath(points, 4).getBounds().width.isFinite,
        isTrue,
      );
    });

    test('the centreline is inside the filled region', () {
      final path = buildVariableWidthPath(line(5), 8);
      expect(path.contains(const Offset(20, 0)), isTrue);
    });

    test('a point beyond the ribbon is outside the filled region', () {
      final path = buildVariableWidthPath(line(5), 8);
      expect(path.contains(const Offset(20, 20)), isFalse);
    });

    test('round caps extend past the endpoints', () {
      // A disc of radius 4 sits on (0, 0), so (-3, 0) is inside.
      final path = buildVariableWidthPath(line(3), 8);
      expect(path.contains(const Offset(-3, 0)), isTrue);
      expect(path.contains(const Offset(-5, 0)), isFalse);
    });

    test('caps do not punch holes where they overlap the ribbon', () {
      // The ribbon and the cap discs wind in opposite directions, so a plain
      // non-zero fill cancels them out and leaves a crescent-shaped hole right
      // at each endpoint. The endpoints themselves must be solid.
      final path = buildVariableWidthPath(line(3), 8);
      expect(path.contains(const Offset(0, 0)), isTrue);
      expect(path.contains(const Offset(20, 0)), isTrue);
      // Just inside the ribbon, next to the start cap.
      expect(path.contains(const Offset(1, 1)), isTrue);
    });

    test('a long random scribble builds without throwing', () {
      // Regression: the caps used to be unioned onto the ribbon with
      // Path.combine, which throws "Path.combine() failed" on the
      // self-intersecting paths a real scribble produces.
      final rnd = math.Random(7);
      final points = [
        for (var i = 0; i < 200; i++)
          StrokePoint(
            x: rnd.nextDouble() * 1900,
            y: rnd.nextDouble() * 1060,
            pressure: rnd.nextDouble(),
          ),
      ];
      expect(() => buildVariableWidthPath(points, 4), returnsNormally);
      expect(buildVariableWidthPath(points, 4).getBounds().isFinite, isTrue);
    });

    test('a stroke crossing itself builds without throwing', () {
      final figureEight = [
        for (var i = 0; i < 64; i++)
          StrokePoint(
            x: 50 + 40 * math.sin(i / 10),
            y: 50 + 40 * math.sin(i / 5),
          ),
      ];
      expect(() => buildVariableWidthPath(figureEight, 12), returnsNormally);
    });
  });
}
