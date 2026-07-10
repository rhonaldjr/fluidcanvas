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

  test('an exhaustive switch covers every variant without a fallback', () {
    expect(describe(stroke), 'stroke');
    expect(describe(shape), 'rectangle');
  });

  test('both variants share the CanvasElement contract', () {
    for (final CanvasElement element in [stroke, shape]) {
      expect(element.id, isNotEmpty);
    }
  });

  test('only a Stroke may have no bounds', () {
    expect(stroke.bounds, isNull);
    expect(shape.bounds, isNotNull);
  });
}
