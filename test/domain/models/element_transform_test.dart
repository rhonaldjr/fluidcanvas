import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';

Stroke strokeAt(double x, double y) => Stroke(
  id: 's',
  colorRGBA: 0xFF0000FF,
  baseWidth: 4,
  points: [
    StrokePoint(x: x, y: y, pressure: 0.5),
    StrokePoint(x: x + 10, y: y + 20),
  ],
);

Shape rectAt(double x, double y, {double rotation = 0}) => Shape(
  id: 'r',
  type: ShapeType.rectangle,
  x: x,
  y: y,
  w: 10,
  h: 20,
  rotation: rotation,
  strokeColorRGBA: 0,
  strokeWidth: 2,
);

void main() {
  group('scaled', () {
    test('scales a stroke about the origin, widening it too', () {
      final s = strokeAt(10, 20).scaled(2);
      expect(s.points.first.x, 20);
      expect(s.points.first.y, 40);
      expect(s.baseWidth, 8);
    });

    test('leaves the origin point fixed', () {
      final s = strokeAt(10, 20).scaled(3, originX: 10, originY: 20);
      expect(s.points.first.x, 10);
      expect(s.points.first.y, 20);
    });

    test('preserves pressure', () {
      expect(strokeAt(0, 0).scaled(2).points.first.pressure, 0.5);
    });

    test('scales a shape box, its stroke width, and not its rotation', () {
      final r = rectAt(4, 6, rotation: 1.2).scaled(2);
      expect(r.x, 8);
      expect(r.y, 12);
      expect(r.w, 20);
      expect(r.h, 40);
      expect(r.strokeWidth, 4);
      expect(r.rotation, 1.2);
    });

    test('bounds scale by the factor', () {
      final before = strokeAt(0, 0).bounds!;
      final after = strokeAt(0, 0).scaled(3).bounds!;
      expect(after.width, closeTo(before.width * 3, 1e-9));
      expect(after.height, closeTo(before.height * 3, 1e-9));
    });

    test('scaled(s) then scaled(1/s) round-trips within float tolerance', () {
      final original = strokeAt(7, 13);
      final round = original
          .scaled(2.5, originX: 3, originY: 4)
          .scaled(1 / 2.5, originX: 3, originY: 4);

      expect(round.points.first.x, closeTo(original.points.first.x, 1e-9));
      expect(round.points.first.y, closeTo(original.points.first.y, 1e-9));
      expect(round.baseWidth, closeTo(original.baseWidth, 1e-9));
    });

    test('rejects a non-positive factor', () {
      expect(() => strokeAt(0, 0).scaled(0), throwsA(isA<AssertionError>()));
      expect(() => rectAt(0, 0).scaled(-1), throwsA(isA<AssertionError>()));
    });

    test('a rotated shape keeps its bounding area ratio', () {
      final before = rectAt(0, 0, rotation: math.pi / 6).bounds;
      final after = rectAt(0, 0, rotation: math.pi / 6).scaled(2).bounds;
      expect(after.width, closeTo(before.width * 2, 1e-9));
      expect(after.height, closeTo(before.height * 2, 1e-9));
    });
  });

  group('translated', () {
    test('moves a stroke without resizing it', () {
      final s = strokeAt(0, 0).translated(5, -3);
      expect(s.points.first.x, 5);
      expect(s.points.first.y, -3);
      expect(s.baseWidth, 4);
    });

    test('moves a shape without touching its size or rotation', () {
      final r = rectAt(1, 2, rotation: 0.4).translated(10, 10);
      expect(r.x, 11);
      expect(r.y, 12);
      expect(r.w, 10);
      expect(r.rotation, 0.4);
    });

    test('is exactly invertible', () {
      final original = rectAt(3, 4);
      expect(original.translated(9, -2).translated(-9, 2), original);
    });

    test('an empty stroke survives both transforms', () {
      final empty = Stroke(id: 'e', colorRGBA: 0, baseWidth: 1);
      expect(empty.scaled(2).points, isEmpty);
      expect(empty.translated(1, 1).points, isEmpty);
    });
  });
}
