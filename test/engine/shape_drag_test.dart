import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/shape_drag.dart';

const anchor = StrokePoint(x: 100, y: 100);

void main() {
  group('dragBox', () {
    test('a corner drag runs from the anchor', () {
      final box = dragBox(
        anchor: anchor,
        current: const StrokePoint(x: 150, y: 130),
      );
      expect((box.x, box.y, box.w, box.h), (100.0, 100.0, 50.0, 30.0));
    });

    test('dragging up and left yields negative extents', () {
      final box = dragBox(
        anchor: anchor,
        current: const StrokePoint(x: 60, y: 40),
      );
      expect(box.w, -40);
      expect(box.h, -60);
      // Which normalize into a real box.
      final s = Shape(
        id: 's',
        type: ShapeType.rectangle,
        x: box.x,
        y: box.y,
        w: box.w,
        h: box.h,
        strokeColorRGBA: 0,
        strokeWidth: 1,
      ).normalized();
      expect((s.x, s.y, s.w, s.h), (60.0, 40.0, 40.0, 60.0));
    });

    group('shift constrains to a square', () {
      test('the larger extent wins, so the box never collapses', () {
        final box = dragBox(
          anchor: anchor,
          current: const StrokePoint(x: 180, y: 110),
          square: true,
        );
        expect(box.w, 80);
        expect(box.h, 80);
      });

      test('the sign of each axis is kept', () {
        final box = dragBox(
          anchor: anchor,
          current: const StrokePoint(x: 20, y: 110),
          square: true,
        );
        expect(box.w, -80);
        expect(box.h, 80);
      });
    });

    group('alt draws from the centre', () {
      test('the anchor ends up in the middle', () {
        final box = dragBox(
          anchor: anchor,
          current: const StrokePoint(x: 130, y: 120),
          fromCenter: true,
        );
        expect(box.x, 70);
        expect(box.y, 80);
        expect(box.w, 60);
        expect(box.h, 40);
        expect(box.x + box.w / 2, anchor.x);
        expect(box.y + box.h / 2, anchor.y);
      });

      test('combines with shift', () {
        final box = dragBox(
          anchor: anchor,
          current: const StrokePoint(x: 140, y: 110),
          square: true,
          fromCenter: true,
        );
        expect(box.w, box.h);
        expect(box.x + box.w / 2, anchor.x);
      });
    });

    test('a zero drag gives a zero box', () {
      final box = dragBox(anchor: anchor, current: anchor);
      expect(box.w, 0);
      expect(box.h, 0);
    });
  });

  group('shapeFromDrag', () {
    test('carries the style through', () {
      final s = shapeFromDrag(
        id: 'x',
        type: ShapeType.ellipse,
        anchor: anchor,
        current: const StrokePoint(x: 200, y: 200),
        strokeColorRGBA: 0xFF0000FF,
        fillColorRGBA: 0x00FF00FF,
        strokeWidth: 5,
        strokeStyle: StrokeStyle.dashed,
      );
      expect(s.type, ShapeType.ellipse);
      expect(s.strokeColorRGBA, 0xFF0000FF);
      expect(s.isFilled, isTrue);
      expect(s.strokeWidth, 5);
      expect(s.strokeStyle, StrokeStyle.dashed);
    });
  });
}
