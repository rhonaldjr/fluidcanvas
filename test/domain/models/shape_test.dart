import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';

Shape shapeWith({
  ShapeType type = ShapeType.rectangle,
  double x = 0,
  double y = 0,
  double w = 10,
  double h = 20,
  double rotation = 0,
  int fillColorRGBA = 0,
  String id = 'sh1',
}) => Shape(
  id: id,
  type: type,
  x: x,
  y: y,
  w: w,
  h: h,
  rotation: rotation,
  fillColorRGBA: fillColorRGBA,
  strokeColorRGBA: 0xFF0000FF,
  strokeWidth: 2,
);

void main() {
  group('ShapeType', () {
    // These numbers are written into .skd files. Changing one silently
    // reinterprets every shape in every file ever saved.
    test('wire values are pinned', () {
      expect(ShapeType.rectangle.value, 0);
      expect(ShapeType.ellipse.value, 1);
      expect(ShapeType.line.value, 2);
      expect(ShapeType.arrow.value, 3);
      expect(ShapeType.diamond.value, 4);
    });

    test('fromValue round-trips every variant', () {
      for (final type in ShapeType.values) {
        expect(ShapeType.fromValue(type.value), type);
      }
    });

    test('fromValue rejects an unknown value rather than guessing', () {
      expect(() => ShapeType.fromValue(99), throwsArgumentError);
      expect(() => ShapeType.fromValue(-1), throwsArgumentError);
    });
  });

  group('StrokeStyle', () {
    test('wire values are pinned', () {
      expect(StrokeStyle.solid.value, 0);
      expect(StrokeStyle.dashed.value, 1);
      expect(StrokeStyle.dotted.value, 2);
    });

    test('fromValue round-trips and rejects the unknown', () {
      for (final style in StrokeStyle.values) {
        expect(StrokeStyle.fromValue(style.value), style);
      }
      expect(() => StrokeStyle.fromValue(7), throwsArgumentError);
    });
  });

  group('construction', () {
    test('defaults to unrotated, unfilled, solid', () {
      final s = shapeWith();
      expect(s.rotation, 0);
      expect(s.isRotated, isFalse);
      expect(s.isFilled, isFalse);
      expect(s.strokeStyle, StrokeStyle.solid);
    });

    test('rejects a non-positive strokeWidth', () {
      expect(
        () => Shape(
          id: 'a',
          type: ShapeType.line,
          x: 0,
          y: 0,
          w: 1,
          h: 1,
          strokeColorRGBA: 0,
          strokeWidth: 0,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('isFilled', () {
    test('alpha 0 means unfilled, whatever the color channels say', () {
      // Opaque-looking red, fully transparent alpha.
      expect(shapeWith(fillColorRGBA: 0xFF000000).isFilled, isFalse);
    });

    test('any non-zero alpha means filled', () {
      expect(shapeWith(fillColorRGBA: 0x00000001).isFilled, isTrue);
      expect(shapeWith(fillColorRGBA: 0xFF0000FF).isFilled, isTrue);
    });
  });

  group('normalized', () {
    test('a positive-extent shape is returned unchanged', () {
      final s = shapeWith(x: 1, y: 2, w: 3, h: 4);
      expect(identical(s.normalized(), s), isTrue);
    });

    test('folds a negative width into x', () {
      final s = shapeWith(x: 10, y: 0, w: -6, h: 5).normalized();
      expect(s.x, 4);
      expect(s.w, 6);
      expect(s.y, 0);
      expect(s.h, 5);
    });

    test('folds a negative height into y', () {
      final s = shapeWith(x: 0, y: 10, w: 5, h: -4).normalized();
      expect(s.y, 6);
      expect(s.h, 4);
    });

    test('folds both, as when dragging up and to the left', () {
      final s = shapeWith(x: 10, y: 10, w: -10, h: -10).normalized();
      expect(s.x, 0);
      expect(s.y, 0);
      expect(s.w, 10);
      expect(s.h, 10);
    });

    test('preserves the center, so rotation stays put', () {
      final flipped = shapeWith(x: 10, y: 10, w: -10, h: -10);
      final s = flipped.normalized();
      expect(s.centerX, flipped.centerX);
      expect(s.centerY, flipped.centerY);
    });

    test('is idempotent', () {
      final once = shapeWith(x: 10, y: 10, w: -10, h: -4).normalized();
      expect(once.normalized(), once);
    });

    test('leaves other fields alone', () {
      final s = shapeWith(
        type: ShapeType.arrow,
        w: -5,
        rotation: 1.2,
      ).normalized();
      expect(s.type, ShapeType.arrow);
      expect(s.rotation, 1.2);
      expect(s.id, 'sh1');
    });
  });

  group('bounds', () {
    test('an unrotated shape bounds its own box exactly', () {
      expect(
        shapeWith(x: 3, y: 4, w: 10, h: 20).bounds,
        const Bounds(left: 3, top: 4, right: 13, bottom: 24),
      );
    });

    test(
      'normalizes first, so a negative-extent shape still bounds correctly',
      () {
        expect(
          shapeWith(x: 13, y: 24, w: -10, h: -20).bounds,
          const Bounds(left: 3, top: 4, right: 13, bottom: 24),
        );
      },
    );

    test('a zero-height line has degenerate but valid bounds', () {
      final b = shapeWith(type: ShapeType.line, w: 10, h: 0).bounds;
      expect(b.isDegenerate, isTrue);
      expect(b.width, 10);
      expect(b.height, 0);
    });

    test('a quarter turn of a square leaves the box unchanged', () {
      final b = shapeWith(
        x: 0,
        y: 0,
        w: 10,
        h: 10,
        rotation: math.pi / 2,
      ).bounds;
      expect(b.left, closeTo(0, 1e-9));
      expect(b.top, closeTo(0, 1e-9));
      expect(b.right, closeTo(10, 1e-9));
      expect(b.bottom, closeTo(10, 1e-9));
    });

    test('a quarter turn of a rectangle swaps width and height', () {
      final b = shapeWith(
        x: 0,
        y: 0,
        w: 10,
        h: 20,
        rotation: math.pi / 2,
      ).bounds;
      expect(b.width, closeTo(20, 1e-9));
      expect(b.height, closeTo(10, 1e-9));
      // Rotation is about the center, which does not move.
      expect(b.centerX, closeTo(5, 1e-9));
      expect(b.centerY, closeTo(10, 1e-9));
    });

    test('45 degrees grows a square box by sqrt(2)', () {
      final b = shapeWith(
        x: 0,
        y: 0,
        w: 10,
        h: 10,
        rotation: math.pi / 4,
      ).bounds;
      final expected = 10 * math.sqrt2;
      expect(b.width, closeTo(expected, 1e-9));
      expect(b.height, closeTo(expected, 1e-9));
      expect(b.centerX, closeTo(5, 1e-9));
      expect(b.centerY, closeTo(5, 1e-9));
    });

    test('rotating never shrinks the bounding area', () {
      // Width and height individually *can* shrink — a 10x20 box turned 90
      // degrees bounds 20x10. Area is the invariant:
      // (w|cos| + h|sin|)(w|sin| + h|cos|) = wh + |sin.cos|(w^2 + h^2) >= wh.
      const area = 10 * 20;
      for (final angle in [0.1, 0.7, 1.4, 2.6, -0.9, math.pi / 2]) {
        final b = shapeWith(w: 10, h: 20, rotation: angle).bounds;
        expect(
          b.width * b.height,
          greaterThanOrEqualTo(area - 1e-9),
          reason: 'angle $angle',
        );
      }
    });

    test(
      'a quarter turn swaps the box extents rather than preserving them',
      () {
        final b = shapeWith(w: 10, h: 20, rotation: math.pi / 2).bounds;
        expect(b.width, closeTo(20, 1e-9));
        expect(b.height, closeTo(10, 1e-9));
      },
    );

    test('a half turn returns the original box', () {
      final b = shapeWith(x: 3, y: 4, w: 10, h: 20, rotation: math.pi).bounds;
      expect(b.left, closeTo(3, 1e-9));
      expect(b.top, closeTo(4, 1e-9));
      expect(b.right, closeTo(13, 1e-9));
      expect(b.bottom, closeTo(24, 1e-9));
    });

    test('rotation is clockwise in screen coordinates', () {
      // y grows downward, so rotating the point (5, -10) from the center of a
      // tall box by +90 degrees must send it to the +x side.
      final b = shapeWith(
        x: 0,
        y: 0,
        w: 2,
        h: 20,
        rotation: math.pi / 2,
      ).bounds;
      expect(b.width, closeTo(20, 1e-9));
    });
  });

  group('copyWith', () {
    final original = shapeWith(x: 1, y: 2, w: 3, h: 4, rotation: 0.5);

    test('replaces only the named fields', () {
      final moved = original.copyWith(x: 99);
      expect(moved.x, 99);
      expect(moved.y, original.y);
      expect(moved.rotation, original.rotation);
      expect(moved.type, original.type);
    });

    test('with no arguments returns an equal shape', () {
      expect(original.copyWith(), original);
    });

    test('can change type without touching geometry', () {
      final ellipse = original.copyWith(type: ShapeType.ellipse);
      expect(ellipse.type, ShapeType.ellipse);
      expect(ellipse.bounds, original.bounds);
    });
  });

  group('value equality', () {
    test('identical field values are equal and share a hashCode', () {
      final a = shapeWith(x: 1, y: 2, rotation: 0.3);
      final b = shapeWith(x: 1, y: 2, rotation: 0.3);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('rotation participates in equality', () {
      expect(shapeWith(rotation: 0), isNot(shapeWith(rotation: 0.1)));
    });

    test('type participates in equality', () {
      expect(
        shapeWith(type: ShapeType.ellipse),
        isNot(shapeWith(type: ShapeType.diamond)),
      );
    });

    test('id participates in equality', () {
      expect(shapeWith(id: 'a'), isNot(shapeWith(id: 'b')));
    });

    test('a normalized shape is not equal to its un-normalized twin', () {
      // Same rectangle geometrically, different field values.
      final flipped = shapeWith(x: 10, y: 0, w: -10, h: 5);
      expect(flipped.normalized(), isNot(flipped));
      expect(flipped.normalized().bounds, flipped.bounds);
    });
  });
}
