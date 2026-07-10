import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/format/format.dart';

Shape shapeAt(String id, double x) => Shape(
  id: id,
  type: ShapeType.rectangle,
  x: x,
  y: 0,
  w: 100,
  h: 100,
  strokeColorRGBA: 0xFF0000FF,
  strokeWidth: 2,
);

/// Round-trips [elements], handing back the decoded list with fixed ids.
List<CanvasElement> roundTrip(List<CanvasElement> elements) {
  var next = 0;
  return decodeElements(encodeElements(elements), idFor: () => 'e${next++}');
}

void main() {
  group('v2 shape render style and seed', () {
    test('a rough shape keeps its style and seed', () {
      final shape = shapeAt(
        's',
        0,
      ).copyWith(renderStyle: ShapeRenderStyle.rough, seed: 0xDEADBEEF);
      final back = roundTrip([shape]).single as Shape;

      expect(back.renderStyle, ShapeRenderStyle.rough);
      expect(back.seed, 0xDEADBEEF);
    });

    test('a precise shape writes a zero style byte, as v1 did', () {
      final bytes = encodeElements([shapeAt('s', 0)]);
      // header 8, then type + 3 reserved, then shapeType, strokeStyle, style.
      expect(bytes[8], ElementType.shape);
      expect(bytes[14], ShapeRenderStyle.precise.value);
    });

    test('the format version is 2', () {
      expect(kSkdFormatVersion, 2);
    });
  });

  group('v2 connectors', () {
    test('a connector with two free ends round-trips', () {
      final connector = Connector(
        id: 'c',
        start: const ConnectorEnd.free(1.5, 2.5),
        end: const ConnectorEnd.free(-3, 4),
        strokeColorRGBA: 0x11223344,
        strokeWidth: 3,
        strokeStyle: StrokeStyle.dashed,
        startArrow: true,
        endArrow: false,
      );
      final back = roundTrip([connector]).single as Connector;

      expect(back.start, const ConnectorEnd.free(1.5, 2.5));
      expect(back.end, const ConnectorEnd.free(-3, 4));
      expect(back.strokeColorRGBA, 0x11223344);
      expect(back.strokeStyle, StrokeStyle.dashed);
      expect(back.startArrow, isTrue);
      expect(back.endArrow, isFalse);
    });

    test('a binding survives as a position, and comes back as the new id', () {
      final connector = Connector(
        id: 'c',
        start: const ConnectorEnd.bound('a'),
        end: const ConnectorEnd.bound('b'),
        strokeColorRGBA: 0xFF,
        strokeWidth: 2,
      );
      final back = roundTrip([shapeAt('a', 0), shapeAt('b', 200), connector]);

      final decoded = back.last as Connector;
      expect(back[0].id, 'e0', reason: 'ids are regenerated');
      expect(decoded.start.elementId, back[0].id);
      expect(decoded.end.elementId, back[1].id);
    });

    test('a connector below what it binds to still resolves', () {
      // The arrow is written first: the reader must not need its target yet.
      final connector = Connector(
        id: 'c',
        start: const ConnectorEnd.bound('a'),
        end: const ConnectorEnd.free(0, 0),
        strokeColorRGBA: 0xFF,
        strokeWidth: 2,
      );
      final back = roundTrip([connector, shapeAt('a', 0)]);

      expect((back.first as Connector).start.elementId, back.last.id);
    });

    test('one bound end and one free end', () {
      final connector = Connector(
        id: 'c',
        start: const ConnectorEnd.bound('a'),
        end: const ConnectorEnd.free(50, 60),
        strokeColorRGBA: 0xFF,
        strokeWidth: 2,
      );
      final back = roundTrip([shapeAt('a', 0), connector]);
      final decoded = back.last as Connector;

      expect(decoded.start.isBound, isTrue);
      expect(decoded.end, const ConnectorEnd.free(50, 60));
    });

    test('a binding to a missing sibling is written as a free end', () {
      // The model should not allow it; the writer must not emit a dangling
      // index either way.
      final connector = Connector(
        id: 'c',
        start: const ConnectorEnd.bound('nobody'),
        end: const ConnectorEnd.free(1, 1),
        strokeColorRGBA: 0xFF,
        strokeWidth: 2,
      );
      final back = roundTrip([connector]).single as Connector;
      expect(back.start.isBound, isFalse);
    });

    test('a connector never binds to another connector', () {
      final first = Connector(
        id: 'c1',
        start: const ConnectorEnd.free(0, 0),
        end: const ConnectorEnd.free(1, 1),
        strokeColorRGBA: 0xFF,
        strokeWidth: 2,
      );
      final second = Connector(
        id: 'c2',
        start: const ConnectorEnd.bound('c1'),
        end: const ConnectorEnd.free(2, 2),
        strokeColorRGBA: 0xFF,
        strokeWidth: 2,
      );
      final back = roundTrip([first, second]);
      expect((back.last as Connector).start.isBound, isFalse);
    });

    test('a non-positive stroke width is rejected', () {
      final bytes = encodeElements([
        Connector(
          id: 'c',
          start: const ConnectorEnd.free(0, 0),
          end: const ConnectorEnd.free(1, 1),
          strokeColorRGBA: 0xFF,
          strokeWidth: 2,
        ),
      ]);
      // Zero the strokeWidth float: 8 header + 4 type/reserved + 4 style bytes
      // + 4 colour = offset 20.
      final corrupt = Uint8List.fromList(bytes);
      final view = corrupt.buffer.asByteData();
      view.setFloat32(20, 0, Endian.little);

      expect(() => decodeElements(corrupt), throwsA(isA<SkdFormatException>()));
    });
  });

  group('v2 groups', () {
    test('a group round-trips with its children', () {
      final group = Group(
        id: 'g',
        children: [shapeAt('a', 0), shapeAt('b', 5)],
      );
      final back = roundTrip([group]).single as Group;

      expect(back.children, hasLength(2));
      expect((back.children.first as Shape).x, 0);
      expect((back.children.last as Shape).x, 5);
    });

    test('nested groups round-trip', () {
      final inner = Group(
        id: 'i',
        children: [shapeAt('a', 0), shapeAt('b', 5)],
      );
      final outer = Group(id: 'o', children: [inner, shapeAt('c', 9)]);
      final back = roundTrip([outer]).single as Group;

      expect(back.children.first, isA<Group>());
      expect((back.children.first as Group).children, hasLength(2));
    });

    test('a connector inside a group binds within the group', () {
      final connector = Connector(
        id: 'x',
        start: const ConnectorEnd.bound('a'),
        end: const ConnectorEnd.bound('b'),
        strokeColorRGBA: 0xFF,
        strokeWidth: 2,
      );
      final group = Group(
        id: 'g',
        children: [shapeAt('a', 0), shapeAt('b', 200), connector],
      );
      final back = roundTrip([group]).single as Group;
      final inside = back.children.last as Connector;

      expect(inside.start.elementId, back.children[0].id);
      expect(inside.end.elementId, back.children[1].id);
    });

    test('a group of one child is a corrupt file, not a group', () {
      final bytes = encodeElements([
        Group(id: 'g', children: [shapeAt('a', 0), shapeAt('b', 5)]),
      ]);
      // Rewrite the group's child count to 1.
      final corrupt = Uint8List.fromList(bytes)
        ..buffer.asByteData().setUint32(12, 1, Endian.little);

      expect(
        () => decodeElements(corrupt),
        throwsA(
          isA<SkdFormatException>().having(
            (e) => e.reason,
            'reason',
            contains('two is the least'),
          ),
        ),
      );
    });

    test('every group id is regenerated too', () {
      final group = Group(
        id: 'g',
        children: [shapeAt('a', 0), shapeAt('b', 5)],
      );
      final back = roundTrip([group]).single as Group;
      expect(back.id, isNot('g'));
      expect(back.children.map((e) => e.id), isNot(contains('a')));
    });
  });

  group('v2 files', () {
    test('a document holding all five element types round-trips', () {
      final now = DateTime.utc(2026, 7, 10);
      final blank = SkdDocument.newDefault(layerId: 'L');
      final document = blank.replaceLayer(
        blank.layers.first.copyWith(
          elements: [
            Stroke(id: 's', colorRGBA: 0xFF, baseWidth: 2),
            shapeAt(
              'a',
              0,
            ).copyWith(renderStyle: ShapeRenderStyle.rough, seed: 7),
            TextElement.plain(id: 't', x: 0, y: 0, w: 10, h: 10, text: 'hi'),
            Connector(
              id: 'c',
              start: const ConnectorEnd.bound('a'),
              end: const ConnectorEnd.free(9, 9),
              strokeColorRGBA: 0xFF,
              strokeWidth: 1,
            ),
            Group(id: 'g', children: [shapeAt('x', 1), shapeAt('y', 2)]),
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
      final back = decodeSkd(bytes).document;
      final elements = back.layers.first.elements;

      expect(elements.map((e) => e.runtimeType.toString()), [
        'Stroke',
        'Shape',
        'TextElement',
        'Connector',
        'Group',
      ]);
      expect((elements[1] as Shape).seed, 7);
      expect((elements[3] as Connector).start.elementId, elements[1].id);
    });
  });
}
