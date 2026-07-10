import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/commands/commands.dart';
import 'package:inkpad/domain/models/models.dart';

Stroke strokeAt(String id, double x) => Stroke(
  id: id,
  colorRGBA: 0x000000FF,
  baseWidth: 4,
  points: [
    StrokePoint(x: x, y: 0),
    StrokePoint(x: x + 10, y: 10),
  ],
);

SkdDocument twoLayerDoc() => SkdDocument(
  canvasWidth: 100,
  canvasHeight: 100,
  layers: [
    Layer(id: 'bottom', name: 'Bottom'),
    Layer(id: 'top', name: 'Top'),
  ],
);

void main() {
  group('AddElementCommand', () {
    test('apply adds the element to the named layer', () {
      final doc = AddElementCommand(
        layerId: 'bottom',
        element: strokeAt('s', 0),
      ).apply(twoLayerDoc());

      expect(doc.layerById('bottom')!.elementCount, 1);
      expect(doc.layerById('top')!.elementCount, 0);
    });

    test('revert removes it again', () {
      final command = AddElementCommand(
        layerId: 'top',
        element: strokeAt('s', 0),
      );
      final original = twoLayerDoc();
      expect(command.revert(command.apply(original)), original);
    });

    test('apply appends on top, preserving z-order', () {
      var doc = twoLayerDoc();
      doc = AddElementCommand(
        layerId: 'top',
        element: strokeAt('a', 0),
      ).apply(doc);
      doc = AddElementCommand(
        layerId: 'top',
        element: strokeAt('b', 20),
      ).apply(doc);

      expect(
        [for (final e in doc.layerById('top')!.elements) e.id],
        ['a', 'b'],
      );
    });

    test('apply is repeatable, as redo requires', () {
      final command = AddElementCommand(
        layerId: 'top',
        element: strokeAt('s', 0),
      );
      final once = command.apply(twoLayerDoc());
      final undone = command.revert(once);
      expect(command.apply(undone), once);
    });

    test('throws when the layer is gone', () {
      final command = AddElementCommand(
        layerId: 'nope',
        element: strokeAt('s', 0),
      );
      expect(() => command.apply(twoLayerDoc()), throwsArgumentError);
      expect(() => command.revert(twoLayerDoc()), throwsArgumentError);
    });

    test('reverting an element that is not there throws', () {
      final command = AddElementCommand(
        layerId: 'top',
        element: strokeAt('s', 0),
      );
      expect(() => command.revert(twoLayerDoc()), throwsArgumentError);
    });

    test('labels a stroke as Draw and a shape as Add Shape', () {
      expect(
        AddElementCommand(layerId: 'top', element: strokeAt('s', 0)).label,
        'Draw',
      );
      expect(
        const AddElementCommand(
          layerId: 'top',
          element: Shape(
            id: 'r',
            type: ShapeType.rectangle,
            x: 0,
            y: 0,
            w: 1,
            h: 1,
            strokeColorRGBA: 0,
            strokeWidth: 1,
          ),
        ).label,
        'Add Shape',
      );
    });

    test('does not mutate the document it is given', () {
      final doc = twoLayerDoc();
      AddElementCommand(layerId: 'top', element: strokeAt('s', 0)).apply(doc);
      expect(doc.elementCount, 0);
    });
  });
}
