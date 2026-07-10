import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/thumbnail.dart';

SkdDocument doc(int w, int h) => SkdDocument(
  canvasWidth: w,
  canvasHeight: h,
  layers: [
    Layer(
      id: 'l',
      name: 'l',
      elements: [
        Stroke(
          id: 's',
          colorRGBA: 0x000000FF,
          baseWidth: 8,
          points: [
            StrokePoint(x: 0, y: 0),
            StrokePoint(x: w / 1.0, y: h / 1.0),
          ],
        ),
      ],
    ),
  ],
);

void main() {
  group('thumbnailSizeFor', () {
    test('fits the longest edge, keeping the aspect ratio', () {
      expect(thumbnailSizeFor(1920, 1080), (width: 256, height: 144));
      expect(thumbnailSizeFor(1080, 1920), (width: 144, height: 256));
    });

    test('a square document stays square', () {
      expect(thumbnailSizeFor(1000, 1000), (width: 256, height: 256));
    });

    test('never upscales a small document', () {
      expect(thumbnailSizeFor(100, 50), (width: 100, height: 50));
    });

    test('never collapses to zero', () {
      final size = thumbnailSizeFor(2000, 1);
      expect(size.height, greaterThanOrEqualTo(1));
    });
  });

  group('renderThumbnailPng', () {
    test('produces a PNG with the right dimensions', () async {
      final png = await renderThumbnailPng(doc(1920, 1080));

      // PNG signature.
      expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      // IHDR carries width and height, big-endian, at bytes 16..24.
      final width =
          (png[16] << 24) | (png[17] << 16) | (png[18] << 8) | png[19];
      final height =
          (png[20] << 24) | (png[21] << 16) | (png[22] << 8) | png[23];
      expect(width, 256);
      expect(height, 144);
      expect(width / height, closeTo(1920 / 1080, 0.01));
    });

    test('an empty document still renders', () async {
      final png = await renderThumbnailPng(
        SkdDocument.newDefault(layerId: 'l'),
      );
      expect(png, isNotEmpty);
    });

    test('a smaller max size gives a smaller image', () async {
      final small = await renderThumbnailPng(doc(800, 600), maxSize: 64);
      final width =
          (small[16] << 24) | (small[17] << 16) | (small[18] << 8) | small[19];
      expect(width, 64);
    });
  });
}
