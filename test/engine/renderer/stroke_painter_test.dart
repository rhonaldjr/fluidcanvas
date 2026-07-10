import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/renderer/stroke_painter.dart';

List<StrokePoint> pointsAt(List<(double, double)> coords) => [
  for (final (x, y) in coords) StrokePoint(x: x, y: y),
];

InProgressStrokePainter painterFor(
  List<StrokePoint> points, {
  double scale = 1,
}) => InProgressStrokePainter(points: points, scale: scale);

void main() {
  group('buildPolylinePath', () {
    test('no points yields an empty path', () {
      expect(buildPolylinePath(const []).getBounds(), Rect.zero);
    });

    test('one point yields a path with no area', () {
      final bounds = buildPolylinePath(pointsAt([(5, 7)])).getBounds();
      expect(bounds.left, 5);
      expect(bounds.top, 7);
      expect(bounds.width, 0);
      expect(bounds.height, 0);
    });

    test('spans the extremes of the points', () {
      final bounds = buildPolylinePath(
        pointsAt([(10, 5), (-3, 20), (4, -8)]),
      ).getBounds();

      expect(bounds.left, -3);
      expect(bounds.top, -8);
      expect(bounds.right, 10);
      expect(bounds.bottom, 20);
    });

    test('path bounds match the stroke model bounds, ignoring width', () {
      final points = pointsAt([(0, 0), (10, 20)]);
      final stroke = Stroke(
        id: 's',
        colorRGBA: 0,
        baseWidth: 40,
        points: points,
      );
      final pathBounds = buildPolylinePath(points).getBounds();

      expect(pathBounds.left, stroke.bounds!.left);
      expect(pathBounds.right, stroke.bounds!.right);
      expect(pathBounds.top, stroke.bounds!.top);
      expect(pathBounds.bottom, stroke.bounds!.bottom);
    });

    test('keeps points in order, so the polyline does not self-cross', () {
      // A zig-zag: bounds alone cannot catch reordering, so check the metric.
      final straight = buildPolylinePath(pointsAt([(0, 0), (10, 0)]));
      final zigzag = buildPolylinePath(pointsAt([(0, 0), (10, 0), (0, 0)]));

      double length(Path p) =>
          p.computeMetrics().fold(0.0, (sum, m) => sum + m.length);

      expect(length(straight), closeTo(10, 1e-9));
      expect(length(zigzag), closeTo(20, 1e-9));
    });
  });

  group('shouldRepaint', () {
    test('repaints when the point list identity changes', () {
      final a = painterFor(pointsAt([(0, 0)]));
      final b = painterFor(pointsAt([(0, 0)]));
      // Different list objects, even with equal contents: the notifier
      // publishes a fresh list per point.
      expect(b.shouldRepaint(a), isTrue);
    });

    test('does not repaint when nothing changed', () {
      final points = pointsAt([(0, 0), (1, 1)]);
      final a = painterFor(points);
      final b = painterFor(points);
      expect(b.shouldRepaint(a), isFalse);
    });

    test('repaints when the scale changes', () {
      final points = pointsAt([(0, 0)]);
      expect(
        painterFor(points, scale: 0.5).shouldRepaint(painterFor(points)),
        isTrue,
      );
    });

    test('repaints when color or width changes', () {
      final points = pointsAt([(0, 0)]);
      final base = InProgressStrokePainter(points: points, scale: 1);
      expect(
        InProgressStrokePainter(
          points: points,
          scale: 1,
          color: Colors.red,
        ).shouldRepaint(base),
        isTrue,
      );
      expect(
        InProgressStrokePainter(
          points: points,
          scale: 1,
          strokeWidth: 9,
        ).shouldRepaint(base),
        isTrue,
      );
    });
  });

  group('paint', () {
    // Verified through recorded canvas size rather than pixels; CLAUDE.md says
    // not to chase pixel-perfect goldens for the canvas. Absolute byte counts
    // are meaningless, so every assertion is relative to an empty recording.
    int recordedBytes(InProgressStrokePainter painter) {
      final recorder = PictureRecorder();
      painter.paint(Canvas(recorder), const Size(100, 100));
      return recorder.endRecording().approximateBytesUsed;
    }

    late int emptyBytes;

    setUp(() {
      emptyBytes = recordedBytes(painterFor(const []));
    });

    test('draws nothing at zero scale', () {
      expect(
        recordedBytes(painterFor(pointsAt([(0, 0), (10, 10)]), scale: 0)),
        emptyBytes,
      );
    });

    test('a single point still paints something', () {
      // A dot, not an empty stroked path that would vanish.
      expect(
        recordedBytes(painterFor(pointsAt([(5, 5)]))),
        greaterThan(emptyBytes),
      );
    });

    test('a polyline paints something', () {
      expect(
        recordedBytes(painterFor(pointsAt([(0, 0), (10, 10), (20, 5)]))),
        greaterThan(emptyBytes),
      );
    });
  });
}
