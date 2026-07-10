import 'dart:io';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/format/format.dart';

void main() {
  final now = DateTime.utc(2026, 7, 10, 12);
  final blank = SkdDocument.newDefault(
    canvasWidth: 800,
    canvasHeight: 600,
    layerId: '11111111-1111-4111-8111-111111111111',
    layerName: 'Diagram',
  );

  Shape box(
    String id,
    double x,
    double y, {
    ShapeRenderStyle? style,
    int seed = 0,
  }) => Shape(
    id: id,
    type: ShapeType.rectangle,
    x: x,
    y: y,
    w: 160,
    h: 90,
    strokeColorRGBA: 0x1B1B1FFF,
    fillColorRGBA: 0xFFF3C4FF,
    strokeWidth: 2,
    renderStyle: style ?? ShapeRenderStyle.precise,
    seed: seed,
  );

  final document = blank.replaceLayer(
    blank.layers.first.copyWith(
      elements: [
        box('a', 60, 60),
        box('b', 520, 380, style: ShapeRenderStyle.rough, seed: 0xC0FFEE),
        Connector(
          id: 'c',
          start: const ConnectorEnd.bound('a'),
          end: const ConnectorEnd.bound('b'),
          strokeColorRGBA: 0xE53935FF,
          strokeWidth: 2,
          strokeStyle: StrokeStyle.dashed,
          endArrow: true,
        ),
        Group(
          id: 'g',
          children: [
            Shape(
              id: 'g1',
              type: ShapeType.ellipse,
              x: 300,
              y: 200,
              w: 100,
              h: 100,
              strokeColorRGBA: 0x1E88E5FF,
              strokeWidth: 3,
              renderStyle: ShapeRenderStyle.rough,
              seed: 42,
            ),
            TextElement.plain(
              id: 'g2',
              x: 300,
              y: 320,
              w: 140,
              h: 40,
              text: 'grüße 😀',
            ),
            Connector(
              id: 'g3',
              start: const ConnectorEnd.bound('g1'),
              end: const ConnectorEnd.free(460, 340),
              strokeColorRGBA: 0x43A047FF,
              strokeWidth: 1.5,
              startArrow: true,
              endArrow: false,
            ),
          ],
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
  File('test/fixtures/v2_golden.skd').writeAsBytesSync(bytes);
  stdout.writeln('wrote ${bytes.length} bytes');
}
