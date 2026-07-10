import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/format/format.dart';

String Function() counter() {
  var n = 0;
  return () => 'e${n++}';
}

SkdManifest manifest() => SkdManifest(
  appVersion: '0.1.0',
  createdUtc: DateTime.utc(2026, 7, 10, 12),
  modifiedUtc: DateTime.utc(2026, 7, 10, 12, 30),
);

SkdDocument sampleDocument() => SkdDocument(
  canvasWidth: 800,
  canvasHeight: 600,
  backgroundRGBA: 0xFAFAFAFF,
  layers: [
    Layer(
      id: 'layer-bottom',
      name: 'Sketch',
      elements: [
        Stroke(
          id: 'e0',
          colorRGBA: 0x1B1B1FFF,
          baseWidth: 4,
          points: const [
            StrokePoint(x: 10, y: 10, pressure: 0.5),
            StrokePoint(x: 200.5, y: 120.25),
          ],
        ),
      ],
    ),
    Layer(
      id: 'layer-top',
      name: 'Shapes',
      opacity: 0.5,
      blendMode: LayerBlendMode.multiply,
      elements: [
        Shape(
          id: 'e1',
          type: ShapeType.ellipse,
          x: 50,
          y: 50,
          w: 120,
          h: 80,
          strokeColorRGBA: 0xE53935FF,
          fillColorRGBA: 0x90CAF9FF,
          strokeWidth: 3,
          strokeStyle: StrokeStyle.dotted,
        ),
        TextElement(
          id: 'e2',
          x: 20,
          y: 300,
          w: 300,
          h: 60,
          fontFamily: 'Helvetica',
          fontSize: 20,
          runs: const [TextRun('hello '), TextRun('world', bold: true)],
        ),
      ],
    ),
  ],
);

void main() {
  group('11.3 writer', () {
    test('mimetype is the first entry and is stored, not compressed', () {
      final bytes = encodeSkd(sampleDocument(), manifest: manifest());
      final archive = ZipDecoder().decodeBytes(bytes);

      expect(archive.files.first.name, 'mimetype');
      expect(archive.files.first.compression, CompressionType.none);
      expect(utf8.decode(archive.files.first.content), kSkdMimeType);
    });

    test('the archive holds one element blob per layer', () {
      final archive = ZipDecoder().decodeBytes(
        encodeSkd(sampleDocument(), manifest: manifest()),
      );
      final names = archive.files.map((f) => f.name).toSet();

      expect(names, containsAll(['manifest.json', 'document.json']));
      expect(names, contains('elements/layer-bottom.bin'));
      expect(names, contains('elements/layer-top.bin'));
      expect(names, isNot(contains('thumbnail.png')));
    });

    test('a thumbnail is included when given', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      final archive = ZipDecoder().decodeBytes(
        encodeSkd(sampleDocument(), manifest: manifest(), thumbnailPng: png),
      );
      expect(archive.findFile('thumbnail.png')!.content, png);
    });

    test('document.json matches the spec', () {
      final archive = ZipDecoder().decodeBytes(
        encodeSkd(sampleDocument(), manifest: manifest()),
      );
      final json =
          jsonDecode(utf8.decode(archive.findFile('document.json')!.content))
              as Map<String, dynamic>;

      expect(json['canvas'], {
        'width': 800,
        'height': 600,
        'background': '#FAFAFA',
      });
      final layers = json['layers'] as List<dynamic>;
      expect(layers, hasLength(2));
      // Bottom to top.
      expect((layers.first as Map)['id'], 'layer-bottom');
      expect((layers.last as Map)['blendMode'], 'multiply');
      expect((layers.last as Map)['elementFile'], 'elements/layer-top.bin');
    });

    test('writes atomically, leaving no temp file behind', () async {
      final dir = await Directory.systemTemp.createTemp('skd');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/a.skd';

      await writeSkdFile(path, sampleDocument(), manifest: manifest());

      expect(File(path).existsSync(), isTrue);
      expect(File('$path.tmp').existsSync(), isFalse);
    });

    test('overwriting replaces the old file', () async {
      final dir = await Directory.systemTemp.createTemp('skd');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/a.skd';

      await writeSkdFile(
        path,
        SkdDocument.newDefault(layerId: 'l'),
        manifest: manifest(),
      );
      final small = File(path).lengthSync();
      await writeSkdFile(path, sampleDocument(), manifest: manifest());

      expect(File(path).lengthSync(), greaterThan(small));
    });
  });

  group('11.4 reader', () {
    test('write then read deep-equals, ids aside', () {
      final original = sampleDocument();
      final bytes = encodeSkd(original, manifest: manifest());
      final read = decodeSkd(bytes, idFor: counter()).document;

      expect(read.canvasWidth, original.canvasWidth);
      expect(read.backgroundRGBA, original.backgroundRGBA);
      expect(read.layerCount, 2);

      // Ids are regenerated, so compare everything else.
      final readShape = read.layers.last.elements[0] as Shape;
      final origShape = original.layers.last.elements[0] as Shape;
      expect(readShape.copyWith(id: origShape.id), origShape);

      final readText = read.layers.last.elements[1] as TextElement;
      final origText = original.layers.last.elements[1] as TextElement;
      expect(readText.copyWith(id: origText.id), origText);
    });

    test('layer properties survive', () {
      final read = decodeSkd(
        encodeSkd(sampleDocument(), manifest: manifest()),
        idFor: counter(),
      ).document;

      expect(read.layers.last.opacity, 0.5);
      expect(read.layers.last.blendMode, LayerBlendMode.multiply);
      expect(read.layers.first.name, 'Sketch');
    });

    test('the manifest comes back', () {
      final read = decodeSkd(encodeSkd(sampleDocument(), manifest: manifest()));
      expect(read.manifest.formatVersion, kSkdFormatVersion);
      expect(read.manifest.appVersion, '0.1.0');
    });

    test('a corrupt archive is rejected', () {
      final junk = Uint8List.fromList(List.filled(200, 7));
      expect(() => decodeSkd(junk), throwsA(isA<SkdFormatException>()));
    });

    test('a zip that is not a .skd is rejected by its mimetype', () {
      final archive = Archive()
        ..addFile(ArchiveFile.string('mimetype', 'text/plain'));
      expect(
        () => decodeSkd(ZipEncoder().encodeBytes(archive)),
        throwsA(
          isA<SkdFormatException>().having(
            (e) => e.reason,
            'reason',
            contains('not a .skd'),
          ),
        ),
      );
    });

    test('formatVersion 999 is rejected with a clear message', () {
      final archive = Archive()
        ..addFile(ArchiveFile.string('mimetype', kSkdMimeType))
        ..addFile(
          ArchiveFile.string(
            'manifest.json',
            jsonEncode({
              'format': 'skd',
              'formatVersion': 999,
              'appVersion': '9',
              'createdUtc': '2026-01-01T00:00:00Z',
              'modifiedUtc': '2026-01-01T00:00:00Z',
            }),
          ),
        );

      expect(
        () => decodeSkd(ZipEncoder().encodeBytes(archive)),
        throwsA(
          isA<SkdFormatException>().having(
            (e) => e.reason,
            'reason',
            contains('newer version'),
          ),
        ),
      );
    });

    test('a missing entry is named in the error', () {
      final archive = Archive()
        ..addFile(ArchiveFile.string('mimetype', kSkdMimeType));
      expect(
        () => decodeSkd(ZipEncoder().encodeBytes(archive)),
        throwsA(
          isA<SkdFormatException>().having(
            (e) => e.reason,
            'reason',
            contains('manifest.json'),
          ),
        ),
      );
    });

    test('a missing file throws rather than returning null', () {
      expect(
        () => readSkdFile('/nonexistent/nope.skd'),
        throwsA(isA<SkdFormatException>()),
      );
    });

    test('a file round-trips through disk', () async {
      final dir = await Directory.systemTemp.createTemp('skd');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/a.skd';

      await writeSkdFile(path, sampleDocument(), manifest: manifest());
      final read = await readSkdFile(path, idFor: counter());
      expect(read.document.elementCount, 3);
    });
  });

  group('document.json validation', () {
    test('unknown blend modes fall back to normal', () {
      // A file from a future version must still open.
      expect(
        documentFromJson({
          'canvas': {'width': 10, 'height': 10, 'background': '#FFFFFF'},
          'layers': [
            {'id': 'a', 'name': 'a', 'blendMode': 'color-dodge'},
          ],
        }, (_) => const []).layers.single.blendMode,
        LayerBlendMode.normal,
      );
    });

    test('a missing required field is an error', () {
      expect(
        () => documentFromJson({'layers': <dynamic>[]}, (_) => const []),
        throwsA(isA<SkdFormatException>()),
      );
    });

    test('zero layers is an error', () {
      expect(
        () => documentFromJson({
          'canvas': {'width': 10, 'height': 10},
          'layers': <dynamic>[],
        }, (_) => const []),
        throwsA(isA<SkdFormatException>()),
      );
    });

    test('duplicate layer ids are an error', () {
      expect(
        () => documentFromJson({
          'canvas': {'width': 10, 'height': 10},
          'layers': [
            {'id': 'a', 'name': 'a'},
            {'id': 'a', 'name': 'b'},
          ],
        }, (_) => const []),
        throwsA(isA<SkdFormatException>()),
      );
    });

    test('a non-positive canvas is an error', () {
      expect(
        () => documentFromJson({
          'canvas': {'width': 0, 'height': 10},
          'layers': [
            {'id': 'a', 'name': 'a'},
          ],
        }, (_) => const []),
        throwsA(isA<SkdFormatException>()),
      );
    });

    test('hex colour conversion round-trips', () {
      expect(rgbToHex(0xFAFAFAFF), '#FAFAFA');
      expect(hexToRgb('#FAFAFA'), 0xFAFAFAFF);
      // Unparseable falls back to white rather than refusing to open.
      expect(hexToRgb('nonsense'), 0xFFFFFFFF);
    });
  });
}
