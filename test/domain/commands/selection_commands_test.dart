import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/commands/commands.dart';
import 'package:inkpad/domain/models/models.dart';

Stroke stroke(String id) => Stroke(
  id: id,
  colorRGBA: 0,
  baseWidth: 4,
  points: const [StrokePoint(x: 0, y: 0), StrokePoint(x: 10, y: 10)],
);

Shape rect(String id) => Shape(
  id: id,
  type: ShapeType.rectangle,
  x: 0,
  y: 0,
  w: 20,
  h: 10,
  strokeColorRGBA: 0x111111FF,
  strokeWidth: 2,
);

SkdDocument docWith(List<CanvasElement> elements) => SkdDocument(
  canvasWidth: 200,
  canvasHeight: 200,
  layers: [Layer(id: 'l', name: 'l', elements: elements)],
);

List<String> ids(SkdDocument d) => [
  for (final e in d.layers.single.elements) e.id,
];

void main() {
  group('MoveElementsCommand', () {
    test('moves and reverts exactly', () {
      final d = docWith([stroke('a'), rect('b')]);
      final command = MoveElementsCommand(
        before: d.layers.single.elements,
        dx: 7,
        dy: -3,
      );
      final moved = command.apply(d);
      expect((moved.findElement('b')!.element as Shape).x, 7);
      expect(command.revert(moved), d);
    });

    test('undo restores the identical objects, so nothing drifts', () {
      final d = docWith([stroke('a')]);
      final command = MoveElementsCommand(
        before: d.layers.single.elements,
        dx: 0.1,
        dy: 0.1,
      );
      final undone = command.revert(command.apply(d));
      expect(
        identical(
          undone.layers.single.elements.single,
          d.layers.single.elements.single,
        ),
        isTrue,
      );
    });

    test('a thousand move/undo cycles leave the geometry untouched', () {
      var d = docWith([stroke('a')]);
      for (var i = 0; i < 1000; i++) {
        final c = MoveElementsCommand(
          before: d.layers.single.elements,
          dx: 0.1,
          dy: 0.3,
        );
        d = c.revert(c.apply(d));
      }
      expect((d.layers.single.elements.single as Stroke).points.first.x, 0);
    });

    test('apply is repeatable', () {
      final d = docWith([rect('b')]);
      final command = MoveElementsCommand(
        before: d.layers.single.elements,
        dx: 5,
        dy: 5,
      );
      final once = command.apply(d);
      expect(command.apply(command.revert(once)), once);
    });
  });

  group('ResizeElementsCommand', () {
    test('scales about the anchor, which stays put', () {
      final d = docWith([rect('b')]);
      final command = ResizeElementsCommand(
        before: d.layers.single.elements,
        factor: 2,
        originX: 0,
        originY: 0,
      );
      final r = command.apply(d).findElement('b')!.element as Shape;
      expect(r.x, 0);
      expect(r.w, 40);
      expect(r.strokeWidth, 4);
    });

    test('reverts exactly, without dividing by the factor', () {
      final d = docWith([stroke('a'), rect('b')]);
      final command = ResizeElementsCommand(
        before: d.layers.single.elements,
        factor: 1.37,
        originX: 3,
        originY: 4,
      );
      expect(command.revert(command.apply(d)), d);
    });

    test('rejects a non-positive factor', () {
      expect(
        () => ResizeElementsCommand(
          before: const [],
          factor: 0,
          originX: 0,
          originY: 0,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('RotateElementsCommand', () {
    test('a shape keeps its box and gains an angle', () {
      final d = docWith([rect('b')]);
      final command = RotateElementsCommand(
        before: d.layers.single.elements,
        radians: math.pi / 4,
        originX: 10,
        originY: 5,
      );
      final r = command.apply(d).findElement('b')!.element as Shape;
      expect(r.rotation, closeTo(math.pi / 4, 1e-9));
      expect(r.w, 20);
    });

    test('a stroke rotates its points', () {
      final d = docWith([stroke('a')]);
      final command = RotateElementsCommand(
        before: d.layers.single.elements,
        radians: math.pi / 2,
        originX: 0,
        originY: 0,
      );
      final s = command.apply(d).findElement('a')!.element as Stroke;
      expect(s.points.last.x, closeTo(-10, 1e-9));
      expect(s.points.last.y, closeTo(10, 1e-9));
    });

    test('reverts exactly', () {
      final d = docWith([stroke('a'), rect('b')]);
      final command = RotateElementsCommand(
        before: d.layers.single.elements,
        radians: 0.37,
        originX: 5,
        originY: 5,
      );
      expect(command.revert(command.apply(d)), d);
    });
  });

  group('StyleElementsCommand', () {
    test('restyles shapes and leaves strokes alone', () {
      final d = docWith([stroke('a'), rect('b')]);
      final command = StyleElementsCommand(
        before: d.layers.single.elements,
        strokeColorRGBA: 0xFF0000FF,
        strokeStyle: StrokeStyle.dashed,
      );
      final after = command.apply(d);
      final shape = after.findElement('b')!.element as Shape;
      expect(shape.strokeColorRGBA, 0xFF0000FF);
      expect(shape.strokeStyle, StrokeStyle.dashed);
      expect(after.findElement('a')!.element, d.findElement('a')!.element);
      expect(command.revert(after), d);
    });
  });

  group('DeleteElementsCommand', () {
    test('deletes and restores each element to its old index', () {
      final d = docWith([stroke('a'), rect('b'), stroke('c')]);
      final command = DeleteElementsCommand(
        removed: [
          (layerId: 'l', index: 0, element: d.layers.single.elements[0]),
          (layerId: 'l', index: 2, element: d.layers.single.elements[2]),
        ],
      );
      final gone = command.apply(d);
      expect(ids(gone), ['b']);

      final back = command.revert(gone);
      expect(ids(back), ['a', 'b', 'c']);
      expect(back, d);
    });

    test('labels itself by count', () {
      final d = docWith([stroke('a')]);
      expect(
        DeleteElementsCommand(
          removed: [
            (layerId: 'l', index: 0, element: d.layers.single.elements[0]),
          ],
        ).label,
        'Delete',
      );
    });
  });

  group('DuplicateElementsCommand', () {
    test('adds copies on top and removes them again', () {
      final d = docWith([rect('b')]);
      final copy = rect('b-copy').translated(10, 10);
      final command = DuplicateElementsCommand(layerId: 'l', copies: [copy]);

      final doubled = command.apply(d);
      expect(ids(doubled), ['b', 'b-copy']);
      expect((doubled.findElement('b-copy')!.element as Shape).x, 10);
      expect(command.revert(doubled), d);
    });
  });

  group('ReorderElementCommand', () {
    test('brings forward and back again', () {
      final d = docWith([stroke('a'), rect('b'), stroke('c')]);
      const command = ReorderElementCommand(
        layerId: 'l',
        oldIndex: 0,
        newIndex: 2,
      );
      final moved = command.apply(d);
      expect(ids(moved), ['b', 'c', 'a']);
      expect(command.revert(moved), d);
    });

    test('labels itself by direction', () {
      expect(
        const ReorderElementCommand(
          layerId: 'l',
          oldIndex: 0,
          newIndex: 1,
        ).label,
        'Bring Forward',
      );
      expect(
        const ReorderElementCommand(
          layerId: 'l',
          oldIndex: 1,
          newIndex: 0,
        ).label,
        'Send Backward',
      );
    });
  });
}
