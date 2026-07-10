import 'dart:io';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/format/format.dart';

void main() {
  final now = DateTime.utc(2026, 7, 10, 12);
  final blank = SkdDocument.newDefault(
    canvasWidth: 800,
    canvasHeight: 600,
    layerId: '22222222-2222-4222-8222-222222222222',
    layerName: 'Rich text',
  );

  final document = blank.replaceLayer(
    blank.layers.first.copyWith(
      elements: [
        TextElement(
          id: 'title',
          x: 60,
          y: 60,
          w: 400,
          h: 200,
          fontSize: 24,
          colorRGBA: 0x1B1B1FFF,
          runs: const [
            TextRun('Big ', fontSize: 48, bold: true),
            TextRun('and '),
            TextRun('red ', colorRGBA: 0xE53935FF),
            TextRun('and ', italic: true),
            TextRun('grüße 😀', fontSize: 30, colorRGBA: 0x1E88E5FF),
          ],
        ),
        const Shape(
          id: 'box',
          type: ShapeType.rectangle,
          x: 500,
          y: 400,
          w: 200,
          h: 120,
          strokeColorRGBA: 0x1B1B1FFF,
          strokeWidth: 3,
        ),
      ],
    ),
  );

  final bytes = encodeSkd(
    document,
    manifest: SkdManifest(
      appVersion: '0.1.0',
      createdUtc: now,
      modifiedUtc: now,
    ),
  );
  File('test/fixtures/v3_golden.skd').writeAsBytesSync(bytes);
  stdout.writeln('wrote ${bytes.length} bytes');
}
