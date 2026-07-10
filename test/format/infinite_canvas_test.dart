import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/format/format.dart';

Uint8List load(String name) => File('test/fixtures/$name').readAsBytesSync();

SkdDocument roundTripJson(SkdDocument document) =>
    documentFromJson(documentToJson(document), (_) => const []);

void main() {
  group('CanvasMode on the model', () {
    test('a document is bounded by default', () {
      expect(SkdDocument.newDefault().canvasMode, CanvasMode.bounded);
      expect(SkdDocument.newDefault().isInfinite, isFalse);
    });

    test('an infinite document reports it', () {
      final doc = SkdDocument.newDefault(canvasMode: CanvasMode.infinite);
      expect(doc.isInfinite, isTrue);
    });

    test('the mode is part of identity', () {
      expect(
        SkdDocument.newDefault(layerId: 'L'),
        isNot(
          SkdDocument.newDefault(layerId: 'L', canvasMode: CanvasMode.infinite),
        ),
      );
    });

    test('an unknown mode string reads as bounded', () {
      expect(CanvasMode.fromValue('galaxy'), CanvasMode.bounded);
      expect(CanvasMode.fromValue(null), CanvasMode.bounded);
    });
  });

  group('document.json', () {
    test('an infinite document round-trips its mode', () {
      final doc = SkdDocument.newDefault(
        layerId: 'L',
        canvasMode: CanvasMode.infinite,
      );
      expect(roundTripJson(doc).canvasMode, CanvasMode.infinite);
    });

    test('a bounded document omits the key entirely', () {
      final json = documentToJson(SkdDocument.newDefault());
      expect((json['canvas'] as Map).containsKey('mode'), isFalse);
    });

    test('an infinite document writes the key', () {
      final json = documentToJson(
        SkdDocument.newDefault(canvasMode: CanvasMode.infinite),
      );
      expect((json['canvas'] as Map)['mode'], 'infinite');
    });

    test('a document with no mode key loads bounded', () {
      final json = documentToJson(SkdDocument.newDefault());
      expect(
        documentFromJson(json, (_) => const []).canvasMode,
        CanvasMode.bounded,
      );
    });
  });

  group('older golden files load bounded', () {
    for (final name in ['v1_golden.skd', 'v2_golden.skd', 'v3_golden.skd']) {
      test('$name is bounded', () {
        expect(decodeSkd(load(name)).document.isInfinite, isFalse);
      });
    }
  });

  group('a full .skd round-trips the mode', () {
    test('infinite survives write and read', () {
      final now = DateTime.utc(2026, 7, 10);
      final doc = SkdDocument.newDefault(
        canvasMode: CanvasMode.infinite,
        layerId: 'L',
      );
      final bytes = encodeSkd(
        doc,
        manifest: SkdManifest(
          appVersion: '0.1.0',
          createdUtc: now,
          modifiedUtc: now,
        ),
      );
      expect(decodeSkd(bytes).document.canvasMode, CanvasMode.infinite);
    });
  });
}
