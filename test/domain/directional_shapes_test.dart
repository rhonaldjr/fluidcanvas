import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/shape_paths.dart';
import 'package:inkpad/format/format.dart';

Shape shape(ShapeType type, double x, double y, double w, double h) => Shape(
  id: 's',
  type: type,
  x: x,
  y: y,
  w: w,
  h: h,
  strokeColorRGBA: 0xFF,
  strokeWidth: 2,
);

Shape roundTrip(Shape s) =>
    decodeElements(encodeElements([s]), idFor: () => 's').single as Shape;

void main() {
  group('directional shapes keep their sign', () {
    test('a line and an arrow are directional; boxes are not', () {
      expect(shape(ShapeType.line, 0, 0, 1, 1).isDirectional, isTrue);
      expect(shape(ShapeType.arrow, 0, 0, 1, 1).isDirectional, isTrue);
      expect(shape(ShapeType.rectangle, 0, 0, 1, 1).isDirectional, isFalse);
      expect(shape(ShapeType.ellipse, 0, 0, 1, 1).isDirectional, isFalse);
      expect(shape(ShapeType.diamond, 0, 0, 1, 1).isDirectional, isFalse);
    });

    test('normalizing a leftward arrow leaves its sign alone', () {
      final arrow = shape(ShapeType.arrow, 100, 100, -50, -50);
      final n = arrow.normalized();
      expect(n.x, 100);
      expect(n.y, 100);
      expect(n.w, -50, reason: 'the arrow still runs up-left from (100,100)');
      expect(n.h, -50);
    });

    test('normalizing a rectangle still folds the sign', () {
      final rect = shape(ShapeType.rectangle, 100, 100, -50, -50);
      final n = rect.normalized();
      expect(n.x, 50);
      expect(n.y, 50);
      expect(n.w, 50);
      expect(n.h, 50);
    });

    test('bounds cover a negative-extent line, corner in either direction', () {
      final line = shape(ShapeType.line, 100, 100, -60, -40);
      expect(
        line.bounds,
        const Bounds(left: 40, top: 60, right: 100, bottom: 100),
      );
    });
  });

  group('the arrow head follows the direction drawn', () {
    test('the head clusters at the far end of a rightward arrow', () {
      final head = arrowHeadAt(const Offset(0, 0), const Offset(100, 0), 2);
      expect(head.getBounds().left, greaterThan(50));
    });

    test('the head clusters at the far end of a leftward arrow', () {
      final head = arrowHeadAt(const Offset(100, 0), const Offset(0, 0), 2);
      expect(head.getBounds().right, lessThan(50));
    });

    test('a shape arrow drawn leftward points its head at the drag end', () {
      // (100,0) with extent (-100,0): the shaft ends at (0,0), head there.
      final head = arrowHeadPath(const Rect.fromLTWH(100, 0, -100, 0), 2);
      expect(head.getBounds().right, lessThan(50));
    });
  });

  group('the format round-trips signed extents', () {
    test('a leftward arrow keeps its direction through save and load', () {
      final back = roundTrip(shape(ShapeType.arrow, 100, 100, -50, -30));
      expect(back.w, -50);
      expect(back.h, -30);
    });

    test('a rectangle is still stored normalized', () {
      final back = roundTrip(shape(ShapeType.rectangle, 100, 100, -50, -30));
      expect(back.x, 50);
      expect(back.w, 50);
    });
  });
}
