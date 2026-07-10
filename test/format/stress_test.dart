import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/format/format.dart';

/// Fixed seeds: a property test that fails only on Tuesdays is not a test.
/// Add a seed here when a fuzz run finds something, and it stays covered.
const List<int> kSeeds = [1, 2, 3, 7, 42, 1337, 20260710];

/// Kept well under the roadmap's ceilings per case; the *total* across seeds
/// is what covers 50 layers and 5000 points, without a ten-minute test run.
const int kMaxLayers = 12;
const int kMaxElements = 60;
const int kMaxPoints = 400;

final _now = DateTime.utc(2026, 7, 10);

SkdManifest _manifest() =>
    SkdManifest(appVersion: '0.1.0', createdUtc: _now, modifiedUtc: _now);

/// A float32 can hold what we generate exactly, so a round trip is equality,
/// not approximation. Anything else would hide a real precision bug.
double _f32(Random random, {double scale = 1000}) =>
    (random.nextDouble() * scale * 2 - scale).toDouble().roundToDouble();

int _rgba(Random random) => random.nextInt(0xFFFFFFFF);

/// An angle that survives float32 exactly: a dyadic fraction of a radian.
///
/// `rotation` is an f32 in the element blob, so 0.97 comes back as
/// 0.9700000286. That is the format, not a bug — but a generator that ignores
/// it tests the reader against a number the file cannot hold.
double _radians(Random random) => random.nextInt(628) / 128;

Stroke _stroke(Random random, String id) => Stroke(
  id: id,
  colorRGBA: _rgba(random),
  baseWidth: (random.nextInt(64) + 1).toDouble(),
  toolId: random.nextBool() ? ToolId.pen : ToolId.eraser,
  points: [
    for (var i = 0; i < random.nextInt(kMaxPoints); i++)
      StrokePoint(
        x: _f32(random),
        y: _f32(random),
        // Pressure survives as float32; use values that are exact in it.
        pressure: random.nextInt(9) / 8,
      ),
  ],
);

Shape _shape(Random random, String id) => Shape(
  id: id,
  type: ShapeType.values[random.nextInt(ShapeType.values.length)],
  x: _f32(random),
  y: _f32(random),
  w: random.nextInt(2000).toDouble(),
  h: random.nextInt(2000).toDouble(),
  rotation: _radians(random),
  strokeColorRGBA: _rgba(random),
  fillColorRGBA: random.nextBool() ? _rgba(random) : 0,
  strokeWidth: (random.nextInt(32) + 1).toDouble(),
  strokeStyle: StrokeStyle.values[random.nextInt(StrokeStyle.values.length)],
);

const _alphabets = [
  'abcdefghijklmnopqrstuvwxyz ',
  'ünïcødé àéîõü ',
  '日本語のテキスト ',
  '😀🎨🖋️ ',
  '\n\t"\\{}',
];

String _text(Random random) {
  final alphabet = _alphabets[random.nextInt(_alphabets.length)];
  final runes = alphabet.runes.toList();
  return String.fromCharCodes([
    for (var i = 0; i < random.nextInt(20) + 1; i++)
      runes[random.nextInt(runes.length)],
  ]);
}

TextElement _textElement(Random random, String id) {
  // Runs are normalized on construction: neighbours with equal styling merge,
  // and empty runs vanish. Generate freely and compare against that rule.
  final runs = <TextRun>[
    for (var i = 0; i < random.nextInt(5) + 1; i++)
      TextRun(
        _text(random),
        bold: random.nextBool(),
        italic: random.nextBool(),
        underline: random.nextBool(),
      ),
  ];
  return TextElement(
    id: id,
    x: _f32(random),
    y: _f32(random),
    w: (random.nextInt(800) + 1).toDouble(),
    h: (random.nextInt(600) + 1).toDouble(),
    rotation: _radians(random),
    fontFamily: random.nextBool() ? '' : _text(random),
    fontSize: (random.nextInt(96) + 4).toDouble(),
    colorRGBA: _rgba(random),
    align: TextAlignment.values[random.nextInt(TextAlignment.values.length)],
    runs: runs,
  );
}

/// A connector, possibly bound to elements already generated in [siblings].
///
/// Bindings are the interesting case: they are stored as an index, not an id,
/// and must come back pointing at the same element.
Connector _connector(Random random, String id, List<CanvasElement> siblings) {
  final bindable = [
    for (final element in siblings)
      if (element is! Connector && element.bounds != null) element.id,
  ];

  ConnectorEnd end() {
    if (bindable.isEmpty || random.nextBool()) {
      return ConnectorEnd.free(_f32(random), _f32(random));
    }
    return ConnectorEnd.bound(bindable[random.nextInt(bindable.length)]);
  }

  return Connector(
    id: id,
    start: end(),
    end: end(),
    strokeColorRGBA: _rgba(random),
    strokeWidth: (random.nextInt(16) + 1).toDouble(),
    strokeStyle: StrokeStyle.values[random.nextInt(StrokeStyle.values.length)],
    startArrow: random.nextBool(),
    endArrow: random.nextBool(),
  );
}

CanvasElement _element(
  Random random,
  String Function() nextId, {
  List<CanvasElement> siblings = const [],
  int depth = 0,
}) {
  // Groups nest, but not without bound: a random walk that keeps grouping
  // would recurse until the stack gave out.
  final kinds = depth < 2 ? 5 : 4;
  return switch (random.nextInt(kinds)) {
    0 => _stroke(random, nextId()),
    1 => _shape(random, nextId()),
    2 => _textElement(random, nextId()),
    3 => _connector(random, nextId(), siblings),
    _ => _group(random, nextId, depth),
  };
}

Group _group(Random random, String Function() nextId, int depth) {
  final children = <CanvasElement>[];
  final count = random.nextInt(3) + 2; // a group holds at least two
  for (var i = 0; i < count; i++) {
    children.add(
      _element(random, nextId, siblings: children, depth: depth + 1),
    );
  }
  return Group(id: nextId(), children: children);
}

SkdDocument _document(Random random) {
  var next = 0;
  String nextId() => 'e${next++}';
  return SkdDocument(
    canvasWidth: random.nextInt(4000) + 1,
    canvasHeight: random.nextInt(4000) + 1,
    // Opaque: `document.json` stores the background as `#RRGGBB`, so its alpha
    // byte lives only in memory. Asserted on its own below.
    backgroundRGBA: _rgba(random) | 0xFF,
    layers: [
      for (var i = 0; i < random.nextInt(kMaxLayers) + 1; i++)
        Layer(
          id: 'layer-$i',
          name: _text(random),
          visible: random.nextBool(),
          opacity: random.nextInt(101) / 100,
          blendMode: LayerBlendMode
              .values[random.nextInt(LayerBlendMode.values.length)],
          elements: _layerElements(random, nextId),
        ),
    ],
  );
}

/// One layer's elements, each able to bind to those already generated below it.
List<CanvasElement> _layerElements(Random random, String Function() nextId) {
  final elements = <CanvasElement>[];
  final count = random.nextInt(kMaxElements);
  for (var i = 0; i < count; i++) {
    elements.add(_element(random, nextId, siblings: elements));
  }
  return elements;
}

/// Element ids are not persisted, so a round trip can only be compared with
/// the ids stripped. Everything else must match exactly.
List<Object> _comparable(SkdDocument document) => [
  document.canvasWidth,
  document.canvasHeight,
  document.backgroundRGBA,
  for (final layer in document.layers) ...[
    layer.name,
    layer.visible,
    layer.opacity,
    layer.blendMode,
    for (final element in layer.elements) _describe(element, layer.elements),
  ],
];

/// Bindings survive as *positions*, not ids, so a comparison has to describe
/// them the same way: "the third element of my container", not "element e7".
Object _describeEnd(ConnectorEnd end, List<CanvasElement> siblings) =>
    end.isBound
    ? 'bound:${siblings.indexWhere((e) => e.id == end.elementId)}'
    : 'free:${end.x},${end.y}';

Object _describe(
  CanvasElement element, [
  List<CanvasElement> siblings = const [],
]) => switch (element) {
  Stroke(:final colorRGBA, :final baseWidth, :final toolId, :final points) => [
    'stroke',
    colorRGBA,
    baseWidth,
    toolId,
    [for (final p in points) (p.x, p.y, p.pressure)],
  ],
  Shape() => [
    'shape',
    element.type,
    element.x,
    element.y,
    element.w,
    element.h,
    element.rotation,
    element.strokeColorRGBA,
    element.fillColorRGBA,
    element.strokeWidth,
    element.strokeStyle,
  ],
  TextElement() => [
    'text',
    element.x,
    element.y,
    element.w,
    element.h,
    element.rotation,
    element.fontFamily,
    element.fontSize,
    element.colorRGBA,
    element.align,
    [
      for (final run in element.runs)
        (run.text, run.bold, run.italic, run.underline),
    ],
  ],
  Connector() => [
    'connector',
    _describeEnd(element.start, siblings),
    _describeEnd(element.end, siblings),
    element.strokeColorRGBA,
    element.strokeWidth,
    element.strokeStyle,
    element.startArrow,
    element.endArrow,
  ],
  Group() => [
    'group',
    [for (final child in element.children) _describe(child, element.children)],
  ],
};

void main() {
  group('15.4 random documents round-trip exactly', () {
    for (final seed in kSeeds) {
      test('seed $seed', () {
        final document = _document(Random(seed));
        final bytes = encodeSkd(document, manifest: _manifest());
        final reread = decodeSkd(bytes).document;

        expect(_comparable(reread), _comparable(document));
        expect(reread.layers, hasLength(document.layers.length));
      });
    }

    test('a document with no elements at all still round-trips', () {
      final document = SkdDocument.newDefault();
      final reread = decodeSkd(
        encodeSkd(document, manifest: _manifest()),
      ).document;
      expect(_comparable(reread), _comparable(document));
    });

    test('a stroke of 5000 points survives', () {
      final random = Random(9);
      final blank = SkdDocument.newDefault();
      final document = blank.replaceLayer(
        blank.layers.first.addElement(
          Stroke(
            id: 's',
            colorRGBA: 0xFF0000FF,
            baseWidth: 3,
            points: [
              for (var i = 0; i < 5000; i++)
                StrokePoint(
                  x: _f32(random),
                  y: _f32(random),
                  pressure: i % 9 / 8,
                ),
            ],
          ),
        ),
      );

      final reread = decodeSkd(
        encodeSkd(document, manifest: _manifest()),
      ).document;
      final stroke = reread.layers.first.elements.single as Stroke;
      expect(stroke.points, hasLength(5000));
      expect(_comparable(reread), _comparable(document));
    });

    test('a translucent background comes back opaque, as the spec says', () {
      // `#RRGGBB` has nowhere to put alpha. Pinned here so a future writer
      // that starts storing it has to change this test deliberately.
      final document = SkdDocument.newDefault(backgroundRGBA: 0x336699AA);
      final reread = decodeSkd(
        encodeSkd(document, manifest: _manifest()),
      ).document;
      expect(reread.backgroundRGBA, 0x336699FF);
    });

    test('rotation is a float32, and says so', () {
      final shape = Shape(
        id: 's',
        type: ShapeType.rectangle,
        x: 0,
        y: 0,
        w: 10,
        h: 10,
        rotation: 0.97,
        strokeColorRGBA: 0xFF,
        strokeWidth: 1,
      );
      final reread = decodeElements(encodeElements([shape])).single as Shape;
      expect(reread.rotation, closeTo(0.97, 1e-6));
      expect(reread.rotation, isNot(0.97), reason: 'f32, not f64');
    });

    test('ids are regenerated, never read from the file', () {
      final document = _document(Random(5));
      final reread = decodeSkd(
        encodeSkd(document, manifest: _manifest()),
        idFor: () => 'fixed',
      ).document;

      final ids = [
        for (final layer in reread.layers)
          for (final element in layer.elements) element.id,
      ];
      expect(ids.every((id) => id == 'fixed'), isTrue);
    });
  });

  group('15.4 the reader never crashes on a mutated file', () {
    /// A valid, small file: every byte of it is a target.
    Uint8List validBytes() =>
        encodeSkd(_document(Random(11)), manifest: _manifest());

    /// Corrupting a ZIP mostly trips its CRC, which is a rejection, not a
    /// crash. What matters is that *nothing* escapes as another exception
    /// type, and that nothing hangs or blows the heap.
    void expectRejectedOrRead(Uint8List bytes) {
      try {
        decodeSkd(bytes);
      } on SkdFormatException {
        return; // The only failure the reader is allowed.
      } on Object catch (error) {
        fail('a mutated file threw ${error.runtimeType}: $error');
      }
    }

    test('flipping any single byte throws only SkdFormatException', () {
      final original = validBytes();
      final random = Random(23);

      for (var i = 0; i < 400; i++) {
        final bytes = Uint8List.fromList(original);
        final at = random.nextInt(bytes.length);
        bytes[at] = bytes[at] ^ (1 << random.nextInt(8));
        expectRejectedOrRead(bytes);
      }
    });

    test('truncating anywhere throws only SkdFormatException', () {
      final original = validBytes();
      for (var cut = 0; cut < original.length; cut += 7) {
        expectRejectedOrRead(Uint8List.sublistView(original, 0, cut));
      }
    });

    test('random noise is rejected, never parsed', () {
      final random = Random(31);
      for (var i = 0; i < 200; i++) {
        final bytes = Uint8List.fromList([
          for (var j = 0; j < random.nextInt(2000); j++) random.nextInt(256),
        ]);
        expectRejectedOrRead(bytes);
      }
    });

    test('a valid zip holding a corrupt element blob is rejected', () {
      final random = Random(37);
      final document = _document(Random(3));

      for (var i = 0; i < 100; i++) {
        final blob = encodeElements(document.layers.first.elements);
        if (blob.length <= 8) continue;
        final at = 8 + random.nextInt(blob.length - 8);
        blob[at] = blob[at] ^ 0xFF;

        try {
          decodeElements(blob);
        } on SkdFormatException {
          continue;
        } on Object catch (error) {
          fail('a corrupt blob threw ${error.runtimeType}: $error');
        }
      }
    });

    test(
      'an element count larger than the blob is rejected, not allocated',
      () {
        // 0xFFFFFFFF elements would be a 100GB list if the reader trusted it.
        final blob = Uint8List(8)
          ..buffer.asByteData().setUint32(0, kElementBlobMagic, Endian.little)
          ..buffer.asByteData().setUint32(4, 0xFFFFFFFF, Endian.little);

        expect(() => decodeElements(blob), throwsA(isA<SkdFormatException>()));
      },
    );

    test('an empty file is rejected', () {
      expectRejectedOrRead(Uint8List(0));
    });
  });
}
