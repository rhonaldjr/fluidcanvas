import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/renderer/brushes.dart';

Stroke strokeOf(int toolId, {int points = 20}) => Stroke(
  id: 's',
  colorRGBA: 0x1B1B1FFF,
  baseWidth: 8,
  toolId: toolId,
  points: [
    for (var i = 0; i < points; i++)
      StrokePoint(x: i * 10.0, y: (i.isEven ? 0 : 6).toDouble(), pressure: 0.8),
  ],
);

Rect boundsOf(Path path) => path.getBounds();

void main() {
  group('brush ids', () {
    test('the new engines have their own tool ids', () {
      expect(ToolId.pencil, 2);
      expect(ToolId.airbrush, 3);
      expect(ToolId.texture, 4);
    });

    test('only the eraser erases', () {
      expect(strokeOf(ToolId.pen).isEraser, isFalse);
      expect(strokeOf(ToolId.eraser).isEraser, isTrue);
      expect(strokeOf(ToolId.pencil).isEraser, isFalse);
      expect(strokeOf(ToolId.airbrush).isEraser, isFalse);
      expect(strokeOf(ToolId.texture).isEraser, isFalse);
    });
  });

  group('the seed is derived from the geometry', () {
    test('the same stroke seeds the same', () {
      expect(
        brushSeed(strokeOf(ToolId.texture)),
        brushSeed(strokeOf(ToolId.texture)),
      );
    });

    test('a different shape seeds differently', () {
      final a = strokeOf(ToolId.texture);
      final b = strokeOf(ToolId.texture, points: 21);
      expect(brushSeed(a), isNot(brushSeed(b)));
    });

    test('the seed does not depend on the tool, only the points', () {
      // A stroke recoloured or re-tooled keeps its grain; only moving a point
      // reshuffles it. The seed reads the points, nothing else.
      final pen = strokeOf(ToolId.pen);
      final texture = strokeOf(ToolId.texture);
      expect(brushSeed(pen), brushSeed(texture));
    });

    test('it is a u32', () {
      expect(
        brushSeed(strokeOf(ToolId.texture)),
        inInclusiveRange(0, 0xFFFFFFFF),
      );
    });
  });

  group('resampleByArcLength', () {
    test('walks the line at even spacing', () {
      final points = [
        const StrokePoint(x: 0, y: 0, pressure: 1),
        const StrokePoint(x: 100, y: 0, pressure: 1),
      ];
      final out = resampleByArcLength(points, 25);
      // 0, 25, 50, 75, 100 — the first point plus each 25px step.
      expect(out.map((p) => p.x.round()), containsAllInOrder([0, 25, 50, 75]));
    });

    test('interpolates pressure along the way', () {
      final points = [
        const StrokePoint(x: 0, y: 0, pressure: 0),
        const StrokePoint(x: 100, y: 0, pressure: 1),
      ];
      final mid = resampleByArcLength(points, 50)[1];
      expect(mid.pressure, closeTo(0.5, 0.001));
    });

    test('a single point is returned unchanged', () {
      final one = [const StrokePoint(x: 5, y: 5, pressure: 1)];
      expect(resampleByArcLength(one, 10), one);
    });

    test('zero spacing does not loop forever', () {
      final points = [
        const StrokePoint(x: 0, y: 0, pressure: 1),
        const StrokePoint(x: 10, y: 0, pressure: 1),
      ];
      expect(resampleByArcLength(points, 0), points);
    });
  });

  group('texture dabs', () {
    test('are deterministic for the same stroke', () {
      final a = buildTextureStamps(strokeOf(ToolId.texture));
      final b = buildTextureStamps(strokeOf(ToolId.texture));
      expect(boundsOf(a), boundsOf(b));
    });

    test('a different seed stamps differently', () {
      final a = buildTextureStamps(strokeOf(ToolId.texture), seed: 1);
      final b = buildTextureStamps(strokeOf(ToolId.texture), seed: 2);
      expect(boundsOf(a), isNot(boundsOf(b)));
    });

    test('stay near the stroke they mark', () {
      final stroke = strokeOf(ToolId.texture);
      final dabs = boundsOf(buildTextureStamps(stroke));
      final line = stroke.bounds!;
      // Within a dab radius of the centreline, not scattered across the page.
      expect(dabs.left, greaterThan(line.left - stroke.baseWidth));
      expect(dabs.right, lessThan(line.right + stroke.baseWidth));
    });

    test('an empty stroke stamps nothing', () {
      final empty = Stroke(
        id: 's',
        colorRGBA: 0,
        baseWidth: 4,
        toolId: ToolId.texture,
      );
      expect(buildTextureStamps(empty).computeMetrics().isEmpty, isTrue);
    });
  });

  group('pencil grain', () {
    test('is deterministic for the same stroke', () {
      final a = buildPencilGrain(strokeOf(ToolId.pencil));
      final b = buildPencilGrain(strokeOf(ToolId.pencil));
      expect(boundsOf(a), boundsOf(b));
    });

    test('a one-point stroke has no grain to draw', () {
      final dot = Stroke(
        id: 's',
        colorRGBA: 0,
        baseWidth: 4,
        toolId: ToolId.pencil,
        points: const [StrokePoint(x: 0, y: 0, pressure: 1)],
      );
      expect(buildPencilGrain(dot).computeMetrics().isEmpty, isTrue);
    });
  });
}
