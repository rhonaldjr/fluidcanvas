import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/format/format.dart';

Uint8List load(String name) => File('test/fixtures/$name').readAsBytesSync();

void main() {
  group('v3 golden fixture', () {
    late SkdFile file;
    setUp(() => file = decodeSkd(load('v3_golden.skd')));

    test('it loads, and says it is v3', () {
      expect(file.manifest.formatVersion, 3);
    });

    test('the title text keeps its per-run sizes and colours', () {
      final title = file.document.layers.single.elements.first as TextElement;
      expect(title.text, 'Big and red and grüße 😀');

      final big = title.runs.firstWhere((r) => r.text.startsWith('Big'));
      expect(big.fontSize, 48);
      expect(big.bold, isTrue);

      final red = title.runs.firstWhere((r) => r.text.startsWith('red'));
      expect(red.colorRGBA, 0xE53935FF);
      expect(red.fontSize, isNull, reason: 'red inherits the element size');

      final greet = title.runs.firstWhere((r) => r.text.contains('😀'));
      expect(greet.fontSize, 30);
      expect(greet.colorRGBA, 0x1E88E5FF);
    });

    test('re-encoding reproduces the same runs', () {
      final now = DateTime.utc(2026, 7, 10, 12);
      final again = decodeSkd(
        encodeSkd(
          file.document,
          manifest: SkdManifest(
            appVersion: '0.1.0',
            createdUtc: now,
            modifiedUtc: now,
          ),
        ),
      ).document;
      final a = again.layers.single.elements.first as TextElement;
      final b = file.document.layers.single.elements.first as TextElement;
      expect(a.runs, b.runs);
    });
  });

  group('v3 still opens older files', () {
    test('the v1 golden loads, with no per-run overrides', () {
      final v1 = decodeSkd(load('v1_golden.skd'));
      expect(v1.manifest.formatVersion, 1);
      final texts = v1.document.layers
          .expand((l) => l.elements)
          .whereType<TextElement>();
      for (final t in texts) {
        for (final run in t.runs) {
          expect(run.fontSize, isNull);
          expect(run.colorRGBA, isNull);
        }
      }
    });

    test('the v2 golden still loads', () {
      final v2 = decodeSkd(load('v2_golden.skd'));
      expect(v2.manifest.formatVersion, 2);
    });
  });
}
