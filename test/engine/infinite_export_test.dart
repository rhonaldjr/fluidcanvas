import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/export_png.dart';

SkdDocument infiniteWith(List<CanvasElement> elements) {
  final blank = SkdDocument.newDefault(
    layerId: 'L',
    canvasMode: CanvasMode.infinite,
  );
  return blank.replaceLayer(blank.layers.first.copyWith(elements: elements));
}

Shape rectAt(double x, double y, double w, double h) => Shape(
  id: 's',
  type: ShapeType.rectangle,
  x: x,
  y: y,
  w: w,
  h: h,
  strokeColorRGBA: 0xFF,
  strokeWidth: 2,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('export region', () {
    test('a bounded document exports its page', () {
      final region = exportRegion(
        SkdDocument.newDefault(canvasWidth: 800, canvasHeight: 600),
      );
      expect(region.width, 800);
      expect(region.height, 600);
      expect(region.left, 0);
    });

    test('an infinite document exports its content, plus a margin', () {
      final region = exportRegion(infiniteWith([rectAt(100, 200, 300, 150)]));
      // Content 100..400 x 200..350, inflated by kInfiniteExportMargin.
      expect(region.left, 100 - kInfiniteExportMargin);
      expect(region.right, 400 + kInfiniteExportMargin);
      expect(region.top, 200 - kInfiniteExportMargin);
    });

    test('handles content in negative space', () {
      final region = exportRegion(infiniteWith([rectAt(-500, -300, 100, 100)]));
      expect(region.left, lessThan(-500));
    });

    test('an empty infinite document exports a small blank tile', () {
      final region = exportRegion(infiniteWith(const []));
      expect(region.width, 256);
      expect(region.height, 256);
    });
  });

  group('export size follows the region', () {
    test('an infinite export is sized to its content at scale', () {
      final doc = infiniteWith([rectAt(0, 0, 200, 100)]);
      final size = exportSizeFor(doc, 2);
      // (200 + 2*margin) * 2 wide.
      expect(size.width, ((200 + 2 * kInfiniteExportMargin) * 2).round());
    });

    test('a real PNG comes out for an infinite document', () async {
      final bytes = await renderDocumentPng(
        infiniteWith([rectAt(0, 0, 50, 50)]),
      );
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });
  });
}
