import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/smoothing.dart';

List<StrokePoint> pointsAt(List<(double, double)> coords) => [
  for (final (x, y) in coords) StrokePoint(x: x, y: y),
];

/// Bounding box of a point list, as (left, top, right, bottom).
(double, double, double, double) boxOf(List<StrokePoint> points) {
  var left = points.first.x, right = left;
  var top = points.first.y, bottom = top;
  for (final p in points) {
    if (p.x < left) left = p.x;
    if (p.x > right) right = p.x;
    if (p.y < top) top = p.y;
    if (p.y > bottom) bottom = p.y;
  }
  return (left, top, right, bottom);
}

void main() {
  group('point counts', () {
    test('an empty stroke smooths to nothing', () {
      expect(smoothStroke(const []), isEmpty);
    });

    test('one point passes through unchanged', () {
      expect(smoothStroke(pointsAt([(1, 2)])), pointsAt([(1, 2)]));
    });

    test('two points pass through unchanged: a straight segment', () {
      expect(smoothStroke(pointsAt([(0, 0), (10, 0)])), hasLength(2));
    });

    test('follows 3 + s*(n-2) for three or more points', () {
      for (final n in [3, 4, 5, 10, 50]) {
        for (final s in [1, 2, 4, 8]) {
          final input = pointsAt([for (var i = 0; i < n; i++) (i * 10.0, 0.0)]);
          expect(
            smoothStroke(input, samplesPerSegment: s),
            hasLength(3 + s * (n - 2)),
            reason: 'n=$n s=$s',
          );
        }
      }
    });

    test('more samples produce more points', () {
      final input = pointsAt([(0, 0), (10, 10), (20, 0)]);
      expect(
        smoothStroke(input, samplesPerSegment: 8).length,
        greaterThan(smoothStroke(input, samplesPerSegment: 2).length),
      );
    });

    test('rejects fewer than one sample per segment', () {
      expect(
        () => StrokeSmoother(samplesPerSegment: 0),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('endpoints', () {
    test('the stroke starts exactly where the input starts', () {
      final input = pointsAt([(3, 4), (10, 10), (20, 0)]);
      final out = smoothStroke(input);
      expect(out.first.x, 3);
      expect(out.first.y, 4);
    });

    test('the stroke ends exactly where the input ends', () {
      final input = pointsAt([(3, 4), (10, 10), (20, 0)]);
      final out = smoothStroke(input);
      expect(out.last.x, 20);
      expect(out.last.y, 0);
    });

    test('interior input points are not passed through', () {
      // Quadratic midpoint smooths corners off; the control point is not on the
      // curve. This is the whole point of it.
      final out = smoothStroke(pointsAt([(0, 0), (10, 10), (20, 0)]));
      expect(out.any((p) => p.x == 10 && p.y == 10), isFalse);
    });
  });

  group('stays within the input bounds', () {
    test('a sharp corner does not overshoot', () {
      // Catmull-Rom would bulge past (10, 10); a convex combination cannot.
      final input = pointsAt([(0, 0), (10, 10), (20, 0)]);
      final (l, t, r, b) = boxOf(input);
      final (ol, ot, or_, ob) = boxOf(smoothStroke(input));

      expect(ol, greaterThanOrEqualTo(l - 1e-9));
      expect(ot, greaterThanOrEqualTo(t - 1e-9));
      expect(or_, lessThanOrEqualTo(r + 1e-9));
      expect(ob, lessThanOrEqualTo(b + 1e-9));
    });

    test('holds for a spiky zig-zag', () {
      final input = pointsAt([
        for (var i = 0; i < 30; i++) (i * 5.0, i.isEven ? 0.0 : 40.0),
      ]);
      final (l, t, r, b) = boxOf(input);
      final (ol, ot, or_, ob) = boxOf(smoothStroke(input));

      expect(ol, greaterThanOrEqualTo(l - 1e-9));
      expect(ot, greaterThanOrEqualTo(t - 1e-9));
      expect(or_, lessThanOrEqualTo(r + 1e-9));
      expect(ob, lessThanOrEqualTo(b + 1e-9));
    });

    test('a straight line stays on the line', () {
      final input = pointsAt([for (var i = 0; i < 8; i++) (i * 10.0, 5.0)]);
      for (final p in smoothStroke(input)) {
        expect(p.y, closeTo(5, 1e-9));
      }
    });

    test('x stays monotonic for a monotonic input', () {
      final input = pointsAt([(0, 0), (10, 5), (20, -5), (30, 5), (40, 0)]);
      final out = smoothStroke(input);
      for (var i = 1; i < out.length; i++) {
        expect(out[i].x, greaterThanOrEqualTo(out[i - 1].x - 1e-9));
      }
    });
  });

  group('pressure', () {
    test('is interpolated, never leaving 0..1', () {
      final input = [
        const StrokePoint(x: 0, y: 0, pressure: 0),
        const StrokePoint(x: 10, y: 0, pressure: 1),
        const StrokePoint(x: 20, y: 0, pressure: 0),
      ];
      for (final p in smoothStroke(input)) {
        expect(p.pressure, inInclusiveRange(0.0, 1.0));
      }
    });

    test('constant pressure stays constant', () {
      final input = [
        for (var i = 0; i < 6; i++)
          StrokePoint(x: i * 10.0, y: 0, pressure: 0.42),
      ];
      for (final p in smoothStroke(input)) {
        expect(p.pressure, closeTo(0.42, 1e-9));
      }
    });

    test('endpoints keep their exact pressure', () {
      final input = [
        const StrokePoint(x: 0, y: 0, pressure: 0.1),
        const StrokePoint(x: 10, y: 0, pressure: 0.5),
        const StrokePoint(x: 20, y: 0, pressure: 0.9),
      ];
      final out = smoothStroke(input);
      expect(out.first.pressure, 0.1);
      expect(out.last.pressure, 0.9);
    });
  });

  group('StrokeSmoother is incremental', () {
    test('streaming matches smoothing the whole list at once', () {
      final input = pointsAt([(0, 0), (10, 10), (20, 0), (30, 10), (40, 0)]);

      final smoother = StrokeSmoother();
      final streamed = <StrokePoint>[];
      for (final p in input) {
        streamed.addAll(smoother.add(p));
      }
      streamed.addAll(smoother.finish());

      final batch = smoothStroke(input);
      expect(streamed.length, batch.length);
      for (var i = 0; i < batch.length; i++) {
        expect(streamed[i].x, closeTo(batch[i].x, 1e-12));
        expect(streamed[i].y, closeTo(batch[i].y, 1e-12));
      }
    });

    test('the first point is emitted immediately', () {
      expect(StrokeSmoother().add(const StrokePoint(x: 1, y: 2)), hasLength(1));
    });

    test('the second point emits nothing: a segment needs a control point', () {
      final smoother = StrokeSmoother()..add(const StrokePoint(x: 0, y: 0));
      expect(smoother.add(const StrokePoint(x: 10, y: 0)), isEmpty);
    });

    test('the third point emits the first segment, including its start', () {
      final smoother = StrokeSmoother(samplesPerSegment: 4)
        ..add(const StrokePoint(x: 0, y: 0))
        ..add(const StrokePoint(x: 10, y: 0));
      // start midpoint + 4 samples
      expect(smoother.add(const StrokePoint(x: 20, y: 0)), hasLength(5));
    });

    test('later points emit exactly one segment each', () {
      final smoother = StrokeSmoother(samplesPerSegment: 4)
        ..add(const StrokePoint(x: 0, y: 0))
        ..add(const StrokePoint(x: 10, y: 0))
        ..add(const StrokePoint(x: 20, y: 0));
      expect(smoother.add(const StrokePoint(x: 30, y: 0)), hasLength(4));
    });

    test('finish emits the pending final input point', () {
      final smoother = StrokeSmoother()
        ..add(const StrokePoint(x: 0, y: 0))
        ..add(const StrokePoint(x: 10, y: 5));
      final tail = smoother.finish();
      expect(tail, hasLength(1));
      expect(tail.single.x, 10);
      expect(tail.single.y, 5);
    });

    test('finish emits nothing for a single-point stroke', () {
      final smoother = StrokeSmoother()..add(const StrokePoint(x: 0, y: 0));
      expect(smoother.finish(), isEmpty);
    });

    test('finish emits nothing for an empty stroke', () {
      expect(StrokeSmoother().finish(), isEmpty);
    });

    test('tracks how many inputs it has seen', () {
      final smoother = StrokeSmoother()
        ..add(const StrokePoint(x: 0, y: 0))
        ..add(const StrokePoint(x: 1, y: 1));
      expect(smoother.inputCount, 2);
    });

    test('rejects adding after finish', () {
      final smoother = StrokeSmoother()..add(const StrokePoint(x: 0, y: 0));
      smoother.finish();
      expect(
        () => smoother.add(const StrokePoint(x: 1, y: 1)),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects finishing twice', () {
      final smoother = StrokeSmoother()..add(const StrokePoint(x: 0, y: 0));
      smoother.finish();
      expect(smoother.finish, throwsA(isA<AssertionError>()));
    });
  });
}
