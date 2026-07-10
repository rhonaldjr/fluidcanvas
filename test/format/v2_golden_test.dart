import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/format/format.dart';

/// Committed by `tool/make_v2_fixture.dart`. Regenerating it is a deliberate
/// act: this file is the promise that today's build can open a v2 drawing
/// forever, exactly as `v1_golden.skd` is for v1.
Uint8List load(String name) => File('test/fixtures/$name').readAsBytesSync();

void main() {
  group('v2 golden fixture', () {
    late SkdFile file;

    setUp(() => file = decodeSkd(load('v2_golden.skd'), idFor: _ids()));

    test('it loads, and says it is v2', () {
      expect(file.manifest.formatVersion, 2);
      expect(file.document.canvasWidth, 800);
      expect(file.document.layers.single.name, 'Diagram');
    });

    test('it holds a shape, a rough shape, a connector and a group', () {
      final elements = file.document.layers.single.elements;
      expect(elements.map((e) => e.runtimeType.toString()), [
        'Shape',
        'Shape',
        'Connector',
        'Group',
      ]);
    });

    test('the rough shape keeps its style and seed', () {
      final rough = file.document.layers.single.elements[1] as Shape;
      expect(rough.renderStyle, ShapeRenderStyle.rough);
      expect(rough.seed, 0xC0FFEE);
    });

    test('the precise shape is still precise', () {
      final precise = file.document.layers.single.elements.first as Shape;
      expect(precise.renderStyle, ShapeRenderStyle.precise);
      expect(precise.seed, 0);
    });

    test('the connector is bound to both boxes, by position', () {
      final elements = file.document.layers.single.elements;
      final connector = elements[2] as Connector;

      expect(connector.start.elementId, elements[0].id);
      expect(connector.end.elementId, elements[1].id);
      expect(connector.strokeStyle, StrokeStyle.dashed);
      expect(connector.endArrow, isTrue);
      expect(connector.startArrow, isFalse);
    });

    test(
      'the group holds its three children, and its connector binds inside',
      () {
        final group = file.document.layers.single.elements[3] as Group;
        expect(group.children, hasLength(3));

        final inner = group.children[2] as Connector;
        expect(inner.start.elementId, group.children[0].id);
        expect(inner.end.isBound, isFalse);
        expect(inner.end.x, 460);
        expect(inner.startArrow, isTrue);
      },
    );

    test('the grouped text keeps its non-ASCII characters', () {
      final group = file.document.layers.single.elements[3] as Group;
      final text = group.children[1] as TextElement;
      expect(text.text, 'grüße 😀');
    });

    test('ids are regenerated, never read from the file', () {
      final ids = <String>[];
      void collect(CanvasElement element) {
        ids.add(element.id);
        if (element is Group) element.children.forEach(collect);
      }

      file.document.layers.single.elements.forEach(collect);
      expect(ids, ['e0', 'e1', 'e2', 'e3', 'e4', 'e5', 'e6']);
    });

    test('re-encoding it reproduces the same model', () {
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
        idFor: _ids(),
      ).document;

      expect(
        again.layers.single.elements,
        file.document.layers.single.elements,
      );
    });
  });

  group('v2 still opens v1', () {
    test('the v1 golden loads under the v2 reader', () {
      final v1 = decodeSkd(load('v1_golden.skd'));
      expect(v1.manifest.formatVersion, 1);
      expect(v1.document.layers, hasLength(3));
    });

    test('a v1 shape reads back as precise, with no seed', () {
      final v1 = decodeSkd(load('v1_golden.skd'));
      final shapes = v1.document.layers
          .expand((l) => l.elements)
          .whereType<Shape>();

      expect(shapes, isNotEmpty);
      for (final shape in shapes) {
        expect(shape.renderStyle, ShapeRenderStyle.precise);
        expect(shape.seed, 0);
      }
    });

    test('a v1 file holds no connectors and no groups', () {
      final elements = decodeSkd(
        load('v1_golden.skd'),
      ).document.layers.expand((l) => l.elements);

      expect(elements.whereType<Connector>(), isEmpty);
      expect(elements.whereType<Group>(), isEmpty);
    });
  });
}

/// Deterministic ids, so a test can name them.
String Function() _ids() {
  var next = 0;
  return () => 'e${next++}';
}
