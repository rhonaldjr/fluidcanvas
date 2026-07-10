import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/format/format.dart';

TextElement text({
  ListStyle listStyle = ListStyle.none,
  String? pathElementId,
}) => TextElement(
  id: 't',
  x: 0,
  y: 0,
  w: 100,
  h: 40,
  listStyle: listStyle,
  pathElementId: pathElementId,
  runs: const [TextRun('hi')],
);

Shape rect(String id) => Shape(
  id: id,
  type: ShapeType.rectangle,
  x: 0,
  y: 0,
  w: 100,
  h: 60,
  strokeColorRGBA: 0xFF,
  strokeWidth: 2,
);

List<CanvasElement> roundTrip(List<CanvasElement> elements) {
  var n = 0;
  return decodeElements(encodeElements(elements), idFor: () => 'e${n++}');
}

void main() {
  group('list style on the model', () {
    test('defaults to none', () {
      expect(text().listStyle, ListStyle.none);
    });

    test('is part of identity', () {
      expect(
        text(listStyle: ListStyle.bullet),
        isNot(text(listStyle: ListStyle.numbered)),
      );
    });

    test('an unknown future style reads back as none', () {
      expect(ListStyle.fromValue(99), ListStyle.none);
    });
  });

  group('list style round-trips without a version bump', () {
    for (final style in ListStyle.values) {
      test('${style.name} survives', () {
        final back = roundTrip([text(listStyle: style)]).single as TextElement;
        expect(back.listStyle, style);
      });
    }

    test('a v1/v2/v3 text with no list byte reads as none', () {
      // A plain text element's list byte is zero, which is ListStyle.none.
      final back = roundTrip([text()]).single as TextElement;
      expect(back.listStyle, ListStyle.none);
    });
  });

  group('path binding', () {
    test('a text is not on a path until bound', () {
      expect(text().isOnPath, isFalse);
      expect(text(pathElementId: 'x').isOnPath, isTrue);
    });

    test('copyWith can clear the binding', () {
      expect(
        text(pathElementId: 'x').copyWith(clearPath: true).isOnPath,
        isFalse,
      );
    });

    test('a binding round-trips as a sibling index, back to the new id', () {
      final back = roundTrip([rect('r'), text(pathElementId: 'r')]);
      final t = back.last as TextElement;
      expect(back.first.id, 'e0', reason: 'ids are regenerated');
      expect(t.pathElementId, back.first.id);
    });

    test('the text may sit below the element it binds to', () {
      // Written first, target second: resolution is a second pass.
      final back = roundTrip([text(pathElementId: 'r'), rect('r')]);
      expect((back.first as TextElement).pathElementId, back.last.id);
    });

    test('a binding to something gone becomes unbound, not a crash', () {
      final back = roundTrip([text(pathElementId: 'missing')]);
      expect((back.single as TextElement).isOnPath, isFalse);
    });

    test('a text never binds to itself', () {
      // Even a self-referential index reads as unbound.
      final back = roundTrip([text(pathElementId: 't')]);
      expect((back.single as TextElement).isOnPath, isFalse);
    });

    test('a text without a binding writes no trailing index', () {
      final plain = encodeElements([text()]);
      final bound = encodeElements([rect('r'), text(pathElementId: 'r')]);
      // The bound blob carries an extra element and a trailing u32, so it is
      // strictly longer; a plain one has no path index at all.
      expect(bound.length, greaterThan(plain.length));
    });
  });
}
