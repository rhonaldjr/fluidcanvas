import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';

/// Names an element without a fallback case.
///
/// This function is the point of the sealed type: adding a `CanvasElement`
/// variant makes it stop compiling until the new case is handled. If a
/// `default` or `_` ever appears here, the guarantee is gone.
String describe(CanvasElement element) => switch (element) {
  Stroke() => 'stroke',
  Shape(type: final type) => type.name,
  TextElement() => 'text',
  Connector() => 'connector',
  Group() => 'group',
};

void main() {
  final stroke = Stroke(id: 's', colorRGBA: 0, baseWidth: 1);
  const shape = Shape(
    id: 'r',
    type: ShapeType.rectangle,
    x: 0,
    y: 0,
    w: 1,
    h: 1,
    strokeColorRGBA: 0,
    strokeWidth: 1,
  );

  final text = TextElement.plain(
    id: 't',
    x: 0,
    y: 0,
    w: 100,
    h: 40,
    text: 'hi',
  );

  final connector = Connector(
    id: 'c',
    start: const ConnectorEnd.free(0, 0),
    end: const ConnectorEnd.bound('r'),
    strokeColorRGBA: 0xFF,
    strokeWidth: 2,
  );
  final group = Group(id: 'g', children: [shape, text]);

  test('an exhaustive switch covers every variant without a fallback', () {
    expect(describe(stroke), 'stroke');
    expect(describe(shape), 'rectangle');
    expect(describe(text), 'text');
    expect(describe(connector), 'connector');
    expect(describe(group), 'group');
  });

  test('both variants share the CanvasElement contract', () {
    for (final CanvasElement element in [stroke, shape]) {
      expect(element.id, isNotEmpty);
    }
  });

  test('a stroke with no points, and a bound connector, have no bounds', () {
    expect(stroke.bounds, isNull);
    expect(shape.bounds, isNotNull);
    // A bound end lands wherever the element it points at is; this object
    // cannot see it. `connectorBounds` resolves it against the siblings.
    expect(connector.bounds, isNull);
    expect(group.bounds, isNotNull);
  });
}
