import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/state/state.dart';

Stroke strokeAt(String id, double x, double y) => Stroke(
  id: id,
  colorRGBA: 0xFF0000FF,
  baseWidth: 2,
  points: [StrokePoint(x: x, y: y)],
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
  group('construction', () {
    test('from() activates the topmost layer', () {
      expect(DocumentSession.from(twoLayerDoc()).activeLayerId, 'top');
    });

    test('blank() opens a default document with its only layer active', () {
      final session = DocumentSession.blank(layerId: 'l1');
      expect(session.activeLayerId, 'l1');
      expect(session.document.isEmpty, isTrue);
      expect(session.document.canvasWidth, 1920);
    });

    test('generates a unique id when none is given', () {
      expect(DocumentSession.blank().id, isNot(DocumentSession.blank().id));
    });

    test('rejects an activeLayerId that names no layer', () {
      expect(
        () => DocumentSession(
          id: 's',
          document: twoLayerDoc(),
          activeLayerId: 'nope',
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('activeLayer resolves to the named layer', () {
      final session = DocumentSession.from(
        twoLayerDoc(),
      ).withActiveLayer('bottom');
      expect(session.activeLayer.name, 'Bottom');
    });
  });

  group('withActiveLayer', () {
    final session = DocumentSession.from(twoLayerDoc(), id: 's');

    test('switches the active layer', () {
      expect(session.withActiveLayer('bottom').activeLayerId, 'bottom');
    });

    test('throws for an unknown layer', () {
      expect(() => session.withActiveLayer('nope'), throwsArgumentError);
    });

    test('does not mutate the original', () {
      session.withActiveLayer('bottom');
      expect(session.activeLayerId, 'top');
    });
  });

  group('withDocument', () {
    final session = DocumentSession.from(
      twoLayerDoc(),
      id: 's',
    ).withActiveLayer('bottom');

    test('keeps the active layer when it survives the swap', () {
      final renamed = session.document.replaceLayer(
        Layer(id: 'bottom', name: 'Renamed'),
      );
      expect(session.withDocument(renamed).activeLayerId, 'bottom');
    });

    test('falls back to the topmost layer when the active one is gone', () {
      // As undoing an AddLayerCommand would, if the added layer was active.
      final without = SkdDocument(
        canvasWidth: 100,
        canvasHeight: 100,
        layers: [Layer(id: 'top', name: 'Top')],
      );
      expect(session.withDocument(without).activeLayerId, 'top');
    });

    test('preserves the session id', () {
      expect(session.withDocument(twoLayerDoc()).id, 's');
    });
  });

  group('addElementToActiveLayer', () {
    test('adds to the active layer, not the topmost', () {
      final session = DocumentSession.from(
        twoLayerDoc(),
        id: 's',
      ).withActiveLayer('bottom').addElementToActiveLayer(strokeAt('a', 0, 0));

      expect(session.document.layerById('bottom')!.elementCount, 1);
      expect(session.document.layerById('top')!.elementCount, 0);
    });

    test('appends on top of the layer, preserving z-order', () {
      final session = DocumentSession.from(twoLayerDoc(), id: 's')
          .addElementToActiveLayer(strokeAt('a', 0, 0))
          .addElementToActiveLayer(strokeAt('b', 0, 0));

      expect([for (final e in session.activeLayer.elements) e.id], ['a', 'b']);
    });

    test('does not mutate the original session', () {
      final original = DocumentSession.from(twoLayerDoc(), id: 's');
      original.addElementToActiveLayer(strokeAt('a', 0, 0));
      expect(original.document.elementCount, 0);
    });
  });

  group('value equality', () {
    test('same id, document, and active layer are equal', () {
      final a = DocumentSession.from(twoLayerDoc(), id: 's');
      final b = DocumentSession.from(twoLayerDoc(), id: 's');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('the document participates in equality', () {
      final a = DocumentSession.from(twoLayerDoc(), id: 's');
      expect(a, isNot(a.addElementToActiveLayer(strokeAt('x', 0, 0))));
    });

    test('the active layer participates in equality', () {
      final a = DocumentSession.from(twoLayerDoc(), id: 's');
      expect(a, isNot(a.withActiveLayer('bottom')));
    });
  });
}
