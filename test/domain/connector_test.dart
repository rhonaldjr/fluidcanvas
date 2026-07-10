import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';

Shape shapeAt(
  String id,
  double x,
  double y, {
  double w = 100,
  double h = 100,
}) => Shape(
  id: id,
  type: ShapeType.rectangle,
  x: x,
  y: y,
  w: w,
  h: h,
  strokeColorRGBA: 0xFF,
  strokeWidth: 2,
);

Connector joining(
  ConnectorEnd start,
  ConnectorEnd end, {
  double strokeWidth = 2,
}) => Connector(
  id: 'c',
  start: start,
  end: end,
  strokeColorRGBA: 0xFF,
  strokeWidth: strokeWidth,
);

void main() {
  // Two boxes side by side, 100 apart: a spans x 0..100, b spans x 200..300.
  final a = shapeAt('a', 0, 0);
  final b = shapeAt('b', 200, 0);
  final siblings = <CanvasElement>[a, b];

  group('17.4 a bound end is derived, never stored', () {
    test('a bound end carries no coordinates', () {
      const end = ConnectorEnd.bound('a');
      expect(end.isBound, isTrue);
      expect(end.x, isNull);
      expect(end.y, isNull);
    });

    test('a connector with a bound end has no standalone bounds', () {
      final connector = joining(
        const ConnectorEnd.bound('a'),
        const ConnectorEnd.free(500, 500),
      );
      expect(connector.bounds, isNull);
      expect(connectorBounds(connector, siblings), isNotNull);
    });

    test('two free ends do have bounds, in either order', () {
      final connector = joining(
        const ConnectorEnd.free(300, 50),
        const ConnectorEnd.free(100, 10),
      );
      expect(
        connector.bounds,
        const Bounds(left: 100, top: 10, right: 300, bottom: 50),
      );
    });

    test('it names what it binds to', () {
      final connector = joining(
        const ConnectorEnd.bound('a'),
        const ConnectorEnd.bound('b'),
      );
      expect(connector.boundIds, {'a', 'b'});
      expect(connector.isBound, isTrue);
    });
  });

  group('17.4 routing', () {
    test('a bound end lands on the box edge facing the other end', () {
      final connector = joining(
        const ConnectorEnd.bound('a'),
        const ConnectorEnd.bound('b'),
      );
      final line = resolveConnector(connector, siblings);

      // Leaves a's right edge (x=100) and reaches b's left edge (x=200),
      // each pushed out by the gap.
      expect(line.x1, closeTo(100 + kConnectorGap, 0.001));
      expect(line.x2, closeTo(200 - kConnectorGap, 0.001));
      expect(line.y1, closeTo(50, 0.001), reason: 'centre height');
      expect(line.y2, closeTo(50, 0.001));
    });

    test('the connector follows the shape when it moves — with no command', () {
      final connector = joining(
        const ConnectorEnd.bound('a'),
        const ConnectorEnd.bound('b'),
      );
      final moved = <CanvasElement>[a, b.translated(0, 400)];

      final before = resolveConnector(connector, siblings);
      final after = resolveConnector(connector, moved);

      expect(after.y2, greaterThan(before.y2));
      // The connector object itself never changed.
      expect(connector.end, const ConnectorEnd.bound('b'));
    });

    test('it leaves through the top when the target is above', () {
      final above = shapeAt('b', 0, -300);
      final connector = joining(
        const ConnectorEnd.bound('a'),
        const ConnectorEnd.bound('b'),
      );
      final line = resolveConnector(connector, [a, above]);

      expect(line.y1, closeTo(0 - kConnectorGap, 0.001), reason: 'a\'s top');
      expect(line.x1, closeTo(50, 0.001));
    });

    test('a free end sits exactly where it says', () {
      final connector = joining(
        const ConnectorEnd.free(500, 600),
        const ConnectorEnd.bound('b'),
      );
      final line = resolveConnector(connector, siblings);
      expect(line.x1, 500);
      expect(line.y1, 600);
    });

    test('two ends bound to the same box do not divide by zero', () {
      final connector = joining(
        const ConnectorEnd.bound('a'),
        const ConnectorEnd.bound('a'),
      );
      final line = resolveConnector(connector, siblings);
      expect(line.x1, line.x2);
      expect(line.y1, line.y2);
    });

    test('a binding to a missing element does not crash', () {
      final connector = joining(
        const ConnectorEnd.bound('gone'),
        const ConnectorEnd.free(50, 50),
      );
      expect(() => resolveConnector(connector, siblings), returnsNormally);
    });

    test('the gap never overshoots a target that is very close', () {
      final touching = shapeAt('b', 101, 0);
      final connector = joining(
        const ConnectorEnd.bound('a'),
        const ConnectorEnd.bound('b'),
      );
      final line = resolveConnector(connector, [a, touching]);
      // The tips must not cross past each other.
      expect(line.x1, lessThanOrEqualTo(line.x2 + 1e-6));
    });

    test('connectors are never anchors for other connectors', () {
      final connector = joining(
        const ConnectorEnd.bound('a'),
        const ConnectorEnd.bound('b'),
      );
      expect(anchorBoxes([a, b, connector]).keys, {'a', 'b'});
    });
  });

  group('17.4 transforms', () {
    test('a free end moves; a bound end does not need to', () {
      final connector = joining(
        const ConnectorEnd.free(10, 20),
        const ConnectorEnd.bound('b'),
      );
      final moved = connector.translated(5, 5);

      expect(moved.start, const ConnectorEnd.free(15, 25));
      expect(moved.end, const ConnectorEnd.bound('b'));
    });

    test('scaling moves free ends and the stroke width', () {
      final connector = joining(
        const ConnectorEnd.free(10, 20),
        const ConnectorEnd.free(30, 40),
      );
      final scaled = connector.scaled(2);

      expect(scaled.start, const ConnectorEnd.free(20, 40));
      expect(scaled.strokeWidth, 4);
    });

    test('rotating a bound end leaves the binding alone', () {
      final connector = joining(
        const ConnectorEnd.bound('a'),
        const ConnectorEnd.free(10, 0),
      );
      final turned = connector.rotated(1.5, originX: 0, originY: 0);
      expect(turned.start, const ConnectorEnd.bound('a'));
      expect(turned.end.x, isNot(10));
    });
  });

  group('17.4 freezing a binding', () {
    test('an end bound to something gone stays where it stood', () {
      final connector = joining(
        const ConnectorEnd.bound('a'),
        const ConnectorEnd.bound('b'),
      );
      final line = resolveConnector(connector, siblings);

      // 'b' is going away; keep only 'a'.
      final frozen = freezeBindingsOutside(connector, {'a'}, siblings);

      expect(frozen.start, const ConnectorEnd.bound('a'));
      expect(frozen.end.isBound, isFalse);
      expect(frozen.end.x, closeTo(line.x2, 0.001));
      expect(frozen.end.y, closeTo(line.y2, 0.001));
    });

    test('nothing to freeze leaves the connector untouched', () {
      final connector = joining(
        const ConnectorEnd.bound('a'),
        const ConnectorEnd.bound('b'),
      );
      expect(freezeBindingsOutside(connector, {'a', 'b'}, siblings), connector);
    });

    test('a connector with no bindings is returned as-is', () {
      final connector = joining(
        const ConnectorEnd.free(0, 0),
        const ConnectorEnd.free(9, 9),
      );
      expect(freezeBindingsOutside(connector, const {}, siblings), connector);
    });
  });

  group('17.4 fresh ids rebind onto the copies', () {
    test('copying a shape and its connector rebinds to the copy', () {
      final connector = joining(
        const ConnectorEnd.bound('a'),
        const ConnectorEnd.bound('b'),
      );
      var next = 0;
      final copies = withFreshIdsAll([a, b, connector], () => 'copy${next++}');

      final copied = copies.last as Connector;
      expect(copied.start.elementId, copies[0].id);
      expect(copied.end.elementId, copies[1].id);
      expect(copies[0].id, isNot('a'));
    });

    test('copying only the connector keeps it bound to the originals', () {
      final connector = joining(
        const ConnectorEnd.bound('a'),
        const ConnectorEnd.free(9, 9),
      );
      final copy = withFreshIds(connector, () => 'copy') as Connector;

      expect(copy.id, 'copy');
      expect(copy.start.elementId, 'a', reason: 'a is still in the document');
    });
  });
}
