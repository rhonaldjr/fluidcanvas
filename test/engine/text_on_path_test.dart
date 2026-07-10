import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/text_layout.dart';
import 'package:inkpad/engine/text_on_path.dart';

Shape rect(String id) => Shape(
  id: id,
  type: ShapeType.rectangle,
  x: 0,
  y: 0,
  w: 200,
  h: 120,
  strokeColorRGBA: 0xFF,
  strokeWidth: 2,
);

Stroke stroke(String id) => Stroke(
  id: id,
  colorRGBA: 0xFF,
  baseWidth: 3,
  points: const [
    StrokePoint(x: 0, y: 0, pressure: 1),
    StrokePoint(x: 100, y: 0, pressure: 1),
  ],
);

TextElement boundText(String pathId) => TextElement(
  id: 't',
  x: 0,
  y: 0,
  w: 100,
  h: 40,
  fontSize: 16,
  pathElementId: pathId,
  runs: const [TextRun('label')],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('list markers', () {
    test('none has no marker', () {
      expect(listMarker(ListStyle.none, 0), isEmpty);
    });

    test('bullet is the same on every line', () {
      expect(listMarker(ListStyle.bullet, 0), listMarker(ListStyle.bullet, 5));
      expect(listMarker(ListStyle.bullet, 0).trim(), '•');
    });

    test('numbered counts from one', () {
      expect(listMarker(ListStyle.numbered, 0).trim(), '1.');
      expect(listMarker(ListStyle.numbered, 4).trim(), '5.');
    });
  });

  group('outlinePathFor', () {
    test('a shape gives its outline', () {
      final path = outlinePathFor(rect('r'), const []);
      expect(path, isNotNull);
      expect(path!.computeMetrics().isEmpty, isFalse);
    });

    test('a stroke gives its centreline', () {
      expect(outlinePathFor(stroke('s'), const []), isNotNull);
    });

    test('a connector gives its resolved line', () {
      final connector = Connector(
        id: 'c',
        start: const ConnectorEnd.free(0, 0),
        end: const ConnectorEnd.free(100, 0),
        strokeColorRGBA: 0xFF,
        strokeWidth: 2,
      );
      expect(outlinePathFor(connector, const []), isNotNull);
    });

    test('a group and a text have no single outline', () {
      final group = Group(id: 'g', children: [rect('a'), rect('b')]);
      expect(outlinePathFor(group, const []), isNull);
      expect(outlinePathFor(boundText('r'), const []), isNull);
    });
  });

  group('bounds and hit-testing follow the path', () {
    final siblings = <CanvasElement>[rect('r'), boundText('r')];

    test('bounds surround the outline, not the text box', () {
      final bounds = textOnPathBounds(boundText('r'), siblings);
      expect(bounds, isNotNull);
      // The rect spans 0..200 x 0..120; padded by the font height.
      expect(bounds!.left, lessThanOrEqualTo(0));
      expect(bounds.right, greaterThanOrEqualTo(200));
    });

    test('a click on the outline hits', () {
      // On the rectangle's top edge.
      expect(hitTextOnPath(boundText('r'), 100, 0, 4, siblings), isTrue);
    });

    test('a click far from the outline misses', () {
      expect(hitTextOnPath(boundText('r'), 100, 600, 4, siblings), isFalse);
    });

    test('an unbound text hits nothing on a path', () {
      final free = boundText('r').copyWith(clearPath: true);
      expect(hitTextOnPath(free, 100, 0, 4, siblings), isFalse);
    });

    test('a binding to a missing sibling is not a crash', () {
      expect(
        () => hitTextOnPath(boundText('gone'), 0, 0, 4, siblings),
        returnsNormally,
      );
    });
  });

  group('painting along a path is safe', () {
    test('it renders without throwing', () {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      final path = outlinePathFor(rect('r'), const [])!;
      expect(
        () => paintTextOnPath(canvas, boundText('r'), path),
        returnsNormally,
      );
      recorder.endRecording().dispose();
    });

    test('an empty text draws nothing and does not throw', () {
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      final empty = TextElement(
        id: 't',
        x: 0,
        y: 0,
        w: 10,
        h: 10,
        pathElementId: 'r',
        runs: const [TextRun('')],
      );
      final path = outlinePathFor(rect('r'), const [])!;
      expect(() => paintTextOnPath(canvas, empty, path), returnsNormally);
      recorder.endRecording().dispose();
    });
  });
}
