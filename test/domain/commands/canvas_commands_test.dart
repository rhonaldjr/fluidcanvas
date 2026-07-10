import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/commands/commands.dart';
import 'package:inkpad/domain/models/models.dart';

Stroke strokeAt(String id, double x, double y) => Stroke(
  id: id,
  colorRGBA: 0,
  baseWidth: 4,
  points: [
    StrokePoint(x: x, y: y),
    StrokePoint(x: x + 100, y: y + 100),
  ],
);

SkdDocument doc({int w = 1000, int h = 1000, List<CanvasElement>? elements}) =>
    SkdDocument(
      canvasWidth: w,
      canvasHeight: h,
      layers: [
        Layer(
          id: 'l',
          name: 'l',
          elements: elements ?? [strokeAt('s', 100, 100)],
        ),
      ],
    );

ResizeCanvasCommand resize(SkdDocument d, int w, int h) => ResizeCanvasCommand(
  oldWidth: d.canvasWidth,
  oldHeight: d.canvasHeight,
  newWidth: w,
  newHeight: h,
  oldLayers: d.layers,
);

Stroke onlyStroke(SkdDocument d) => d.layers.single.elements.single as Stroke;

void main() {
  group('factor', () {
    test('is the tighter axis, so nothing is stretched', () {
      final d = doc();
      expect(resize(d, 2000, 1000).factor, 1.0);
      expect(resize(d, 2000, 3000).factor, 2.0);
      expect(resize(d, 500, 1000).factor, 0.5);
    });

    test('rejects a degenerate size', () {
      expect(
        () => ResizeCanvasCommand(
          oldWidth: 10,
          oldHeight: 10,
          newWidth: 0,
          newHeight: 10,
          oldLayers: const [],
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('apply', () {
    test('doubles the canvas and the drawing', () {
      final d = doc();
      final grown = resize(d, 2000, 2000).apply(d);

      expect(grown.canvasWidth, 2000);
      expect(onlyStroke(grown).baseWidth, 8);
      // (100,100) is 400 left/up of the old centre (500,500); after a 2x scale
      // it is 800 from the new centre (1000,1000).
      expect(onlyStroke(grown).points.first.x, closeTo(200, 1e-9));
      expect(onlyStroke(grown).points.first.y, closeTo(200, 1e-9));
    });

    test('keeps the drawing centred when the aspect changes', () {
      final d = doc();
      // Widening only: factor is 1, so the drawing keeps its size and shifts
      // right by half the added width.
      final wide = resize(d, 2000, 1000).apply(d);
      expect(wide.canvasWidth, 2000);
      expect(onlyStroke(wide).baseWidth, 4);
      expect(onlyStroke(wide).points.first.x, closeTo(600, 1e-9));
      expect(onlyStroke(wide).points.first.y, closeTo(100, 1e-9));
    });

    test('preserves the relative composition of two strokes', () {
      final d = doc(
        elements: [strokeAt('a', 100, 100), strokeAt('b', 300, 100)],
      );
      final grown = resize(d, 2000, 2000).apply(d);
      final a = grown.layers.single.elements[0] as Stroke;
      final b = grown.layers.single.elements[1] as Stroke;

      final gapBefore = 300.0 - 100.0;
      expect(b.points.first.x - a.points.first.x, closeTo(gapBefore * 2, 1e-9));
      expect(a.points.first.y, closeTo(b.points.first.y, 1e-9));
    });

    test('an empty document resizes without complaint', () {
      final d = SkdDocument.newDefault(layerId: 'l');
      final grown = resize(d, 800, 600).apply(d);
      expect(grown.canvasWidth, 800);
      expect(grown.isEmpty, isTrue);
    });

    test('is repeatable, as redo requires', () {
      final d = doc();
      final command = resize(d, 2000, 2000);
      final once = command.apply(d);
      expect(command.apply(command.revert(once)), once);
    });
  });

  group('revert is exact', () {
    test('undo restores the original document', () {
      final d = doc();
      final command = resize(d, 1737, 991);
      expect(command.revert(command.apply(d)), d);
    });

    test('undo restores the identical element objects, not scaled copies', () {
      // revert() hands back the captured list, so no float drift can creep in.
      final d = doc();
      final command = resize(d, 333, 777);
      final undone = command.revert(command.apply(d));
      expect(
        identical(
          undone.layers.single.elements.single,
          d.layers.single.elements.single,
        ),
        isTrue,
      );
    });

    test('a hundred resize/undo cycles leave the geometry untouched', () {
      // Reverting by dividing by the factor would drift; restoring the captured
      // layers cannot.
      var d = doc();
      for (var i = 0; i < 100; i++) {
        final command = resize(d, 700 + i, 1300 - i);
        d = command.revert(command.apply(d));
      }
      expect(onlyStroke(d).points.first.x, 100);
      expect(onlyStroke(d).baseWidth, 4);
    });

    test('the command holds an unmodifiable copy of the old layers', () {
      final d = doc();
      final command = resize(d, 800, 800);
      expect(
        () => command.oldLayers.add(Layer(id: 'x', name: 'x')),
        throwsUnsupportedError,
      );
    });
  });
}
