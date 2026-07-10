import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/rough.dart';
import 'package:inkpad/engine/shape_paths.dart';

const _rect = Rect.fromLTWH(10, 20, 200, 120);

/// A path's shape, as numbers a test can compare.
///
/// Never the rendered pixels: this is geometry, and the point of a seeded
/// wobble is that the geometry is reproducible.
List<double> metrics(Path path) {
  final box = path.getBounds();
  var length = 0.0;
  for (final metric in path.computeMetrics()) {
    length += metric.length;
  }
  return [box.left, box.top, box.right, box.bottom, length];
}

void main() {
  group('17.1 the noise is pure', () {
    test('the same seed and index always give the same value', () {
      expect(roughNoise(7, 3), roughNoise(7, 3));
      expect(roughNoise(0, 0), roughNoise(0, 0));
    });

    test('different indices give different values', () {
      expect(roughNoise(7, 3), isNot(roughNoise(7, 4)));
    });

    test('different seeds give different values at the same index', () {
      expect(roughNoise(7, 3), isNot(roughNoise(8, 3)));
    });

    test('it stays within [-1, 1]', () {
      for (var seed = 0; seed < 50; seed++) {
        for (var i = 0; i < 50; i++) {
          final value = roughNoise(seed, i);
          expect(value, inInclusiveRange(-1, 1), reason: 'seed $seed, $i');
        }
      }
    });

    test('it is not constant, and not all one sign', () {
      final values = [for (var i = 0; i < 200; i++) roughNoise(42, i)];
      expect(values.toSet().length, greaterThan(150));
      expect(values.any((v) => v > 0.2), isTrue);
      expect(values.any((v) => v < -0.2), isTrue);
    });
  });

  group('17.1 the wobble is deterministic', () {
    for (final type in ShapeType.values) {
      test('${type.name} draws identically twice', () {
        final a = buildRoughPath(type, _rect, seed: 99, strokeWidth: 2);
        final b = buildRoughPath(type, _rect, seed: 99, strokeWidth: 2);
        expect(metrics(a), metrics(b));
      });

      test('${type.name} draws differently under a different seed', () {
        final a = buildRoughPath(type, _rect, seed: 1, strokeWidth: 2);
        final b = buildRoughPath(type, _rect, seed: 2, strokeWidth: 2);
        expect(metrics(a), isNot(metrics(b)));
      });
    }

    test('a rough path is longer than the precise one it wobbles around', () {
      final precise = metrics(buildShapePath(ShapeType.rectangle, _rect)).last;
      final rough = metrics(
        buildRoughPath(ShapeType.rectangle, _rect, seed: 5),
      ).last;
      // Two passes, each at least as long as the perimeter.
      expect(rough, greaterThan(precise * 1.9));
    });

    test('the wobble stays near the shape it is wobbling', () {
      final path = buildRoughPath(ShapeType.rectangle, _rect, seed: 5);
      final slack = roughOffsetFor(_rect) + 1;
      final box = path.getBounds();

      expect(box.left, greaterThan(_rect.left - slack));
      expect(box.top, greaterThan(_rect.top - slack));
      expect(box.right, lessThan(_rect.right + slack));
      expect(box.bottom, lessThan(_rect.bottom + slack));
    });
  });

  group('17.1 the wobble scales with the shape', () {
    test('a big shape wobbles more than a tiny one, up to a cap', () {
      expect(
        roughOffsetFor(const Rect.fromLTWH(0, 0, 20, 20)),
        lessThan(roughOffsetFor(const Rect.fromLTWH(0, 0, 300, 300))),
      );
      expect(
        roughOffsetFor(const Rect.fromLTWH(0, 0, 5000, 5000)),
        kMaxRoughOffset,
      );
    });

    test('a zero-size shape falls back to the precise path', () {
      const flat = Rect.fromLTWH(10, 10, 0, 40);
      expect(
        metrics(buildRoughPath(ShapeType.rectangle, flat, seed: 3)),
        metrics(buildShapePath(ShapeType.rectangle, flat)),
      );
    });

    test('a negative box does not invert the wobble amount', () {
      expect(
        roughOffsetFor(const Rect.fromLTRB(100, 100, 20, 20)),
        greaterThan(0),
      );
    });
  });

  group('17.1 the model carries the style', () {
    const shape = Shape(
      id: 's',
      type: ShapeType.rectangle,
      x: 0,
      y: 0,
      w: 100,
      h: 50,
      strokeColorRGBA: 0xFF,
      strokeWidth: 2,
    );

    test('a shape is precise until it is asked not to be', () {
      expect(shape.isRough, isFalse);
      expect(shape.renderStyle, ShapeRenderStyle.precise);
      expect(shape.seed, 0);
    });

    test('resizing keeps the seed, so the wobble does not reshuffle', () {
      final rough = shape.copyWith(
        renderStyle: ShapeRenderStyle.rough,
        seed: 12345,
      );
      expect(rough.scaled(2).seed, 12345);
      expect(rough.translated(10, 10).seed, 12345);
      expect(rough.rotated(1, originX: 0, originY: 0).seed, 12345);
      expect(rough.scaled(2).renderStyle, ShapeRenderStyle.rough);
    });

    test('the seed and style are part of the shape\'s identity', () {
      expect(shape.copyWith(seed: 1), isNot(shape.copyWith(seed: 2)));
      expect(shape.copyWith(renderStyle: ShapeRenderStyle.rough), isNot(shape));
    });

    test('an unknown future render style reads back as precise', () {
      // Unlike an unknown elementType, this costs nothing to ignore.
      expect(ShapeRenderStyle.fromValue(99), ShapeRenderStyle.precise);
    });

    test('a seed derived from an id is stable across runs', () {
      expect(seedFromId('abc'), seedFromId('abc'));
      expect(seedFromId('abc'), isNot(seedFromId('abd')));
      expect(seedFromId('abc'), inInclusiveRange(0, 0xFFFFFFFF));
    });
  });
}
