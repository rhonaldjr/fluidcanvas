import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/hit_test.dart';

Stroke lineStroke({double width = 4}) => Stroke(
  id: 's',
  colorRGBA: 0,
  baseWidth: width,
  points: const [StrokePoint(x: 0, y: 0), StrokePoint(x: 100, y: 0)],
);

Shape box({
  ShapeType type = ShapeType.rectangle,
  int fill = 0,
  double rotation = 0,
  double strokeWidth = 2,
}) => Shape(
  id: 'r',
  type: type,
  x: 50,
  y: 50,
  w: 100,
  h: 60,
  rotation: rotation,
  strokeColorRGBA: 0,
  fillColorRGBA: fill,
  strokeWidth: strokeWidth,
);

void main() {
  group('strokes', () {
    test('a click on the line hits', () {
      expect(hitTestElement(lineStroke(), 50, 0), isTrue);
    });

    test(
      'a click just off the line hits, within tolerance and half the width',
      () {
        expect(hitTestElement(lineStroke(), 50, 5), isTrue);
      },
    );

    test('a click well away misses', () {
      expect(hitTestElement(lineStroke(), 50, 40), isFalse);
    });

    test('a thicker stroke is easier to hit', () {
      expect(hitTestElement(lineStroke(), 50, 12), isFalse);
      expect(hitTestElement(lineStroke(width: 24), 50, 12), isTrue);
    });

    test('past the ends it misses', () {
      expect(hitTestElement(lineStroke(), -20, 0), isFalse);
      expect(hitTestElement(lineStroke(), 120, 0), isFalse);
    });

    test('an empty stroke is never hit', () {
      expect(
        hitTestElement(Stroke(id: 'e', colorRGBA: 0, baseWidth: 4), 0, 0),
        isFalse,
      );
    });

    test('a single-point stroke is hit near its dot', () {
      final dot = Stroke(
        id: 'd',
        colorRGBA: 0,
        baseWidth: 10,
        points: const [StrokePoint(x: 10, y: 10)],
      );
      expect(hitTestElement(dot, 12, 12), isTrue);
      expect(hitTestElement(dot, 40, 40), isFalse);
    });
  });

  group('shapes', () {
    test('an unfilled rectangle is grabbable only near its outline', () {
      // You can click through the middle, as every drawing tool lets you.
      expect(hitTestElement(box(), 100, 80), isFalse);
      expect(hitTestElement(box(), 50, 80), isTrue);
      expect(hitTestElement(box(), 100, 50), isTrue);
    });

    test('a filled rectangle is grabbable anywhere inside', () {
      expect(hitTestElement(box(fill: 0xFF0000FF), 100, 80), isTrue);
    });

    test('a filled line has no interior, so only its outline hits', () {
      final line = box(type: ShapeType.line, fill: 0xFF0000FF);
      // The line runs corner to corner; its centre is on it.
      expect(hitTestElement(line, 100, 80), isTrue);
      // A point far off the diagonal is not.
      expect(hitTestElement(line, 60, 100), isFalse);
    });

    test('an ellipse misses the corners of its box', () {
      final e = box(type: ShapeType.ellipse, fill: 0xFF0000FF);
      expect(hitTestElement(e, 100, 80), isTrue);
      expect(hitTestElement(e, 52, 52), isFalse);
    });

    test('rotation is honoured', () {
      final turned = box(rotation: math.pi / 2, fill: 0xFF0000FF);
      // The box is 100x60 about its centre (100, 80); turned, it is 60x100.
      expect(hitTestElement(turned, 100, 130), isTrue);
      expect(hitTestElement(turned, 145, 80), isFalse);
    });

    test('a negative-extent shape is normalized before testing', () {
      final flipped = box().copyWith(x: 150, y: 110, w: -100, h: -60);
      expect(hitTestElement(flipped, 50, 80), isTrue);
    });
  });

  group('elementsAt', () {
    final layers = [
      Layer(id: 'a', name: 'a', elements: [lineStroke()]),
      Layer(id: 'b', name: 'b', elements: [box(fill: 0xFF0000FF)]),
    ];

    test('returns the topmost first', () {
      final hits = elementsAt(layers, 100, 80);
      expect(hits.single.id, 'r');
    });

    test('topmostElementAt picks what a click would grab', () {
      expect(topmostElementAt(layers, 50, 0)!.id, 's');
      expect(topmostElementAt(layers, 400, 400), isNull);
    });

    test('a hidden layer cannot be clicked', () {
      final hidden = [
        Layer(
          id: 'b',
          name: 'b',
          visible: false,
          elements: [box(fill: 0xFF0000FF)],
        ),
      ];
      expect(topmostElementAt(hidden, 100, 80), isNull);
    });

    test('overlapping elements: the one on top wins', () {
      final stacked = [
        Layer(
          id: 'a',
          name: 'a',
          elements: [
            box(fill: 0xFF0000FF).copyWith(id: 'under'),
            box(fill: 0xFF0000FF).copyWith(id: 'over'),
          ],
        ),
      ];
      expect(topmostElementAt(stacked, 100, 80)!.id, 'over');
    });
  });

  group('elementsWithin', () {
    final layers = [
      Layer(id: 'a', name: 'a', elements: [lineStroke(), box()]),
    ];

    test('selects only what lies wholly inside', () {
      final all = elementsWithin(
        layers,
        const Bounds(left: -50, top: -50, right: 400, bottom: 400),
      );
      expect(all, hasLength(2));

      final justStroke = elementsWithin(
        layers,
        const Bounds(left: -10, top: -10, right: 110, bottom: 10),
      );
      expect(justStroke.single.id, 's');
    });

    test('a partially covered element is not selected', () {
      final partial = elementsWithin(
        layers,
        const Bounds(left: 0, top: 0, right: 50, bottom: 50),
      );
      expect(partial, isEmpty);
    });
  });
}
