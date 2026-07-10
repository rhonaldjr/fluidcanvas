import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';

Stroke strokeWith(List<StrokePoint> points, {String id = 's1'}) =>
    Stroke(id: id, colorRGBA: 0xFF0000FF, baseWidth: 4, points: points);

void main() {
  group('construction', () {
    test('defaults to the pen tool and no points', () {
      final s = Stroke(id: 's1', colorRGBA: 0xFF0000FF, baseWidth: 4);
      expect(s.toolId, ToolId.pen);
      expect(s.isEraser, isFalse);
      expect(s.points, isEmpty);
    });

    test('an eraser stroke reports itself as one', () {
      final s = Stroke(
        id: 's1',
        colorRGBA: 0,
        baseWidth: 4,
        toolId: ToolId.eraser,
      );
      expect(s.isEraser, isTrue);
    });

    test('rejects a non-positive baseWidth', () {
      expect(
        () => Stroke(id: 's1', colorRGBA: 0, baseWidth: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => Stroke(id: 's1', colorRGBA: 0, baseWidth: -1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('points are unmodifiable, so a Stroke cannot be mutated in place', () {
      final s = strokeWith(const [StrokePoint(x: 0, y: 0)]);
      expect(
        () => s.points.add(const StrokePoint(x: 1, y: 1)),
        throwsUnsupportedError,
      );
    });

    test(
      'copies the incoming list, so later caller mutation cannot leak in',
      () {
        final source = [const StrokePoint(x: 0, y: 0)];
        final s = strokeWith(source);
        source.add(const StrokePoint(x: 99, y: 99));
        expect(s.points, hasLength(1));
      },
    );
  });

  group('bounds', () {
    test('a stroke with no points has no bounds', () {
      expect(strokeWith(const []).bounds, isNull);
    });

    test('a single point yields a zero-size box at that point', () {
      final b = strokeWith(const [StrokePoint(x: 5, y: 7)]).bounds!;
      expect(b, const Bounds.point(5, 7));
      expect(b.width, 0);
      expect(b.height, 0);
    });

    test('spans the extremes of all points, in any order', () {
      final b = strokeWith(const [
        StrokePoint(x: 10, y: 5),
        StrokePoint(x: -3, y: 20),
        StrokePoint(x: 4, y: -8),
      ]).bounds!;
      expect(b, const Bounds(left: -3, top: -8, right: 10, bottom: 20));
    });

    test('ignores baseWidth; the ink extends past the geometry', () {
      final thin = Stroke(
        id: 's',
        colorRGBA: 0,
        baseWidth: 1,
        points: const [StrokePoint(x: 0, y: 0), StrokePoint(x: 10, y: 0)],
      );
      final thick = thin.copyWith(baseWidth: 40);
      expect(thick.bounds, thin.bounds);
      // Callers that need painted extent inflate by half the width.
      expect(thick.bounds!.inflate(20).top, -20);
    });

    test('a horizontal stroke is degenerate but still has bounds', () {
      final b = strokeWith(const [
        StrokePoint(x: 0, y: 3),
        StrokePoint(x: 10, y: 3),
      ]).bounds!;
      expect(b.isDegenerate, isTrue);
      expect(b.width, 10);
      expect(b.height, 0);
    });
  });

  group('copyWith', () {
    final original = strokeWith(const [StrokePoint(x: 1, y: 1)]);

    test('replaces only the named fields', () {
      final recolored = original.copyWith(colorRGBA: 0x00FF00FF);
      expect(recolored.colorRGBA, 0x00FF00FF);
      expect(recolored.id, original.id);
      expect(recolored.points, original.points);
    });

    test('with no arguments returns an equal stroke', () {
      expect(original.copyWith(), original);
    });

    test('can switch a pen stroke to an eraser', () {
      expect(original.copyWith(toolId: ToolId.eraser).isEraser, isTrue);
    });
  });

  group('addPoint', () {
    test('appends without mutating the original', () {
      final original = strokeWith(const [StrokePoint(x: 0, y: 0)]);
      final extended = original.addPoint(const StrokePoint(x: 1, y: 1));

      expect(original.points, hasLength(1));
      expect(extended.points, hasLength(2));
      expect(extended.points.last, const StrokePoint(x: 1, y: 1));
    });

    test('grows the bounds', () {
      final s = strokeWith(const [
        StrokePoint(x: 0, y: 0),
      ]).addPoint(const StrokePoint(x: 10, y: 10));
      expect(s.bounds, const Bounds(left: 0, top: 0, right: 10, bottom: 10));
    });
  });

  group('value equality', () {
    test('identical field values are equal and share a hashCode', () {
      final a = strokeWith(const [StrokePoint(x: 1, y: 2, pressure: 0.5)]);
      final b = strokeWith(const [StrokePoint(x: 1, y: 2, pressure: 0.5)]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('compares points deeply, not by reference', () {
      final a = strokeWith(const [StrokePoint(x: 1, y: 2)]);
      final b = strokeWith(const [StrokePoint(x: 1, y: 3)]);
      expect(a, isNot(b));
    });

    test('point count participates in equality', () {
      final a = strokeWith(const [StrokePoint(x: 1, y: 2)]);
      expect(a, isNot(a.addPoint(const StrokePoint(x: 1, y: 2))));
    });

    test('id participates in equality', () {
      expect(
        strokeWith(const [], id: 'a'),
        isNot(strokeWith(const [], id: 'b')),
      );
    });

    test('two empty strokes with the same id are equal', () {
      expect(strokeWith(const []), strokeWith(const []));
    });
  });
}
