import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/export_png.dart';

/// The eight-byte PNG signature. What "is this a PNG" means.
const List<int> _pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

SkdDocument doc({
  int width = 40,
  int height = 30,
  int background = 0xFFFFFFFF,
}) => SkdDocument.newDefault(
  canvasWidth: width,
  canvasHeight: height,
  backgroundRGBA: background,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('15.1 export size', () {
    test('1x is the document size', () {
      expect(exportSizeFor(doc(), 1), (width: 40, height: 30));
    });

    test('2x and 4x multiply both axes', () {
      expect(exportSizeFor(doc(), 2), (width: 80, height: 60));
      expect(exportSizeFor(doc(), 4), (width: 160, height: 120));
    });

    test('the offered scales are 1x, 2x and 4x', () {
      expect(kExportScales, [1, 2, 4]);
    });
  });

  group('15.1 rendering', () {
    test('produces a PNG at the document size', () async {
      final bytes = await renderDocumentPng(doc());
      expect(bytes.sublist(0, 8), _pngMagic);
      expect(bytes, isNotEmpty);
    });

    test('a 4x export is larger than a 1x one', () async {
      final small = await renderDocumentPng(doc(), scale: 1);
      final large = await renderDocumentPng(doc(), scale: 4);
      expect(large.length, greaterThan(small.length));
    });

    test('a transparent export differs from an opaque one', () async {
      final opaque = await renderDocumentPng(doc());
      final clear = await renderDocumentPng(doc(), transparentBackground: true);
      expect(clear, isNot(opaque));
      expect(clear.sublist(0, 8), _pngMagic);
    });

    test('an empty document still exports', () async {
      final bytes = await renderDocumentPng(doc());
      expect(bytes.sublist(0, 8), _pngMagic);
    });

    test('a scale below 1 is refused with a reason', () {
      expect(
        () => renderDocumentPng(doc(), scale: 0),
        throwsA(isA<ExportException>()),
      );
    });

    test('an export too large to rasterize is refused, not attempted', () {
      // 8192 x 8192 at 4x is 32768 on a side: four gigabytes of surface.
      expect(
        () => renderDocumentPng(doc(width: 8192, height: 8192), scale: 4),
        throwsA(
          isA<ExportException>().having(
            (e) => e.reason,
            'reason',
            contains('larger than this build can render'),
          ),
        ),
      );
    });

    test('a hidden layer is not exported', () async {
      final blank = doc();
      final drawn = blank.replaceLayer(
        blank.layers.first.addElement(
          const Shape(
            id: 's',
            type: ShapeType.rectangle,
            x: 5,
            y: 5,
            w: 20,
            h: 15,
            strokeColorRGBA: 0xFF0000FF,
            fillColorRGBA: 0xFF0000FF,
            strokeWidth: 2,
          ),
        ),
      );
      final hidden = drawn.replaceLayer(
        drawn.layers.first.copyWith(visible: false),
      );

      // Not a pixel assertion: drawing changes the bytes, and hiding the layer
      // undoes that change exactly, because it never reaches the canvas.
      expect(
        await renderDocumentPng(drawn),
        isNot(await renderDocumentPng(blank)),
      );
      expect(await renderDocumentPng(hidden), await renderDocumentPng(blank));
    });
  });
}
