import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/commands/commands.dart';
import 'package:inkpad/domain/models/models.dart';

Stroke stroke(String id) => Stroke(
  id: id,
  colorRGBA: 0,
  baseWidth: 2,
  points: const [StrokePoint(x: 0, y: 0), StrokePoint(x: 5, y: 5)],
);

SkdDocument docWith(List<Layer> layers) =>
    SkdDocument(canvasWidth: 100, canvasHeight: 100, layers: layers);

List<String> ids(SkdDocument d) => [for (final l in d.layers) l.id];

void main() {
  group('SkdDocument layer surgery', () {
    test('insertLayer places the layer bottom-first', () {
      final doc = docWith([Layer(id: 'a', name: 'a')]);
      expect(ids(doc.insertLayer(0, Layer(id: 'z', name: 'z'))), ['z', 'a']);
      expect(ids(doc.insertLayer(1, Layer(id: 'z', name: 'z'))), ['a', 'z']);
    });

    test('insertLayer rejects a duplicate id or a bad index', () {
      final doc = docWith([Layer(id: 'a', name: 'a')]);
      expect(
        () => doc.insertLayer(0, Layer(id: 'a', name: 'dup')),
        throwsArgumentError,
      );
      expect(
        () => doc.insertLayer(2, Layer(id: 'z', name: 'z')),
        throwsRangeError,
      );
    });

    test('removeLayer refuses the last layer', () {
      final doc = docWith([Layer(id: 'a', name: 'a')]);
      expect(() => doc.removeLayer('a'), throwsStateError);
    });

    test('removeLayer rejects an unknown id', () {
      final doc = docWith([
        Layer(id: 'a', name: 'a'),
        Layer(id: 'b', name: 'b'),
      ]);
      expect(() => doc.removeLayer('nope'), throwsArgumentError);
    });

    test('moveLayer indices address the resulting list', () {
      final doc = docWith([
        Layer(id: 'a', name: 'a'),
        Layer(id: 'b', name: 'b'),
        Layer(id: 'c', name: 'c'),
      ]);
      expect(ids(doc.moveLayer(0, 2)), ['b', 'c', 'a']);
      expect(ids(doc.moveLayer(2, 0)), ['c', 'a', 'b']);
      expect(identical(doc.moveLayer(1, 1), doc), isTrue);
    });
  });

  group('AddLayerCommand', () {
    test('apply inserts, revert removes', () {
      final doc = docWith([Layer(id: 'a', name: 'a')]);
      final command = AddLayerCommand(
        layer: Layer(id: 'z', name: 'z'),
        index: 1,
      );

      final added = command.apply(doc);
      expect(ids(added), ['a', 'z']);
      expect(command.revert(added), doc);
    });

    test('apply is repeatable after a revert', () {
      final doc = docWith([Layer(id: 'a', name: 'a')]);
      final command = AddLayerCommand(
        layer: Layer(id: 'z', name: 'z'),
        index: 0,
      );
      final once = command.apply(doc);
      expect(command.apply(command.revert(once)), once);
    });
  });

  group('DeleteLayerCommand', () {
    final doc = docWith([
      Layer(id: 'a', name: 'a', elements: [stroke('s')]),
      Layer(id: 'b', name: 'b'),
    ]);

    test(
      'apply removes, revert restores it with its contents and position',
      () {
        final command = DeleteLayerCommand(layer: doc.layers.first, index: 0);
        final deleted = command.apply(doc);

        expect(ids(deleted), ['b']);
        final restored = command.revert(deleted);
        expect(ids(restored), ['a', 'b']);
        // The strokes come back too: the command carries the whole layer.
        expect(restored.layerById('a')!.elementCount, 1);
        expect(restored, doc);
      },
    );

    test('deleting the last layer is refused', () {
      final single = docWith([Layer(id: 'a', name: 'a')]);
      final command = DeleteLayerCommand(layer: single.layers.first, index: 0);
      expect(() => command.apply(single), throwsStateError);
    });
  });

  group('ReorderLayerCommand', () {
    final doc = docWith([
      Layer(id: 'a', name: 'a'),
      Layer(id: 'b', name: 'b'),
      Layer(id: 'c', name: 'c'),
    ]);

    test('apply moves, revert moves back', () {
      const command = ReorderLayerCommand(oldIndex: 0, newIndex: 2);
      final moved = command.apply(doc);
      expect(ids(moved), ['b', 'c', 'a']);
      expect(command.revert(moved), doc);
    });

    test('round-trips for a downward move too', () {
      const command = ReorderLayerCommand(oldIndex: 2, newIndex: 0);
      expect(command.revert(command.apply(doc)), doc);
    });
  });

  group('RenameLayerCommand', () {
    test('apply renames, revert restores the old name', () {
      final doc = docWith([Layer(id: 'a', name: 'Old')]);
      const command = RenameLayerCommand(
        layerId: 'a',
        oldName: 'Old',
        newName: 'New',
      );

      final renamed = command.apply(doc);
      expect(renamed.layerById('a')!.name, 'New');
      expect(command.revert(renamed), doc);
    });

    test('throws for a missing layer', () {
      final doc = docWith([Layer(id: 'a', name: 'a')]);
      const command = RenameLayerCommand(
        layerId: 'nope',
        oldName: 'x',
        newName: 'y',
      );
      expect(() => command.apply(doc), throwsArgumentError);
    });
  });

  group('SetLayerOpacityCommand', () {
    test('apply sets, revert restores', () {
      final doc = docWith([Layer(id: 'a', name: 'a')]);
      const command = SetLayerOpacityCommand(
        layerId: 'a',
        oldOpacity: 1,
        newOpacity: 0.4,
      );

      final faded = command.apply(doc);
      expect(faded.layerById('a')!.opacity, 0.4);
      expect(command.revert(faded), doc);
    });

    test('leaves the elements alone, so the layer cache stays warm', () {
      final layer = Layer(id: 'a', name: 'a', elements: [stroke('s')]);
      final doc = docWith([layer]);
      const command = SetLayerOpacityCommand(
        layerId: 'a',
        oldOpacity: 1,
        newOpacity: 0.5,
      );
      final faded = command.apply(doc);
      expect(identical(faded.layerById('a')!.elements, layer.elements), isTrue);
    });
  });

  group('SetLayerVisibilityCommand', () {
    test('apply hides, revert shows', () {
      final doc = docWith([Layer(id: 'a', name: 'a')]);
      const command = SetLayerVisibilityCommand(layerId: 'a', visible: false);

      final hidden = command.apply(doc);
      expect(hidden.layerById('a')!.visible, isFalse);
      expect(command.revert(hidden), doc);
    });

    test('labels itself by what it will do', () {
      expect(
        const SetLayerVisibilityCommand(layerId: 'a', visible: false).label,
        'Hide Layer',
      );
      expect(
        const SetLayerVisibilityCommand(layerId: 'a', visible: true).label,
        'Show Layer',
      );
    });
  });
}
