import 'dart:convert';
import 'dart:typed_data';

import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/format/skd_exception.dart';
import 'package:uuid/uuid.dart';

/// "SKD1", little-endian.
const int kElementBlobMagic = 0x534B4431;

/// The `elementType` discriminator. These numbers are the file format: never
/// reassign one, only append.
abstract final class ElementType {
  static const int stroke = 0;
  static const int shape = 1;
  static const int text = 2;
  static const int connector = 3;
  static const int group = 4;
}

/// A connector end's `kind` byte.
abstract final class ConnectorEndKind {
  static const int free = 0;
  static const int bound = 1;
}

/// The index a bound end writes when the element it names is not among its
/// siblings — which the writer treats as a bug, and the reader as a free end.
const int kNoBinding = 0xFFFFFFFF;

/// Encodes a layer's elements into the binary blob stored at
/// `elements/<layer-uuid>.bin`.
///
/// Element ids are **not** written: they are regenerated on load, and nothing
/// in the format may reference an element by id.
Uint8List encodeElements(List<CanvasElement> elements) {
  final out = _ByteWriter()
    ..uint32(kElementBlobMagic)
    ..uint32(elements.length);

  for (final element in elements) {
    _writeElement(out, element, elements);
  }
  return out.takeBytes();
}

/// Writes one element record: type, three reserved bytes, then the body.
///
/// [siblings] is the list [element] lives in, needed only by a [Connector]: a
/// bound end is stored as the **index** of what it binds to, because ids are
/// regenerated on load and the format may not reference one.
void _writeElement(
  _ByteWriter out,
  CanvasElement element,
  List<CanvasElement> siblings,
) {
  switch (element) {
    case Stroke():
      out
        ..uint8(ElementType.stroke)
        ..reserved(3);
      _writeStroke(out, element);
    case Shape():
      out
        ..uint8(ElementType.shape)
        ..reserved(3);
      _writeShape(out, element);
    case TextElement():
      out
        ..uint8(ElementType.text)
        ..reserved(3);
      _writeText(out, element, siblings);
    case Connector():
      out
        ..uint8(ElementType.connector)
        ..reserved(3);
      _writeConnector(out, element, siblings);
    case Group():
      out
        ..uint8(ElementType.group)
        ..reserved(3);
      _writeGroup(out, element);
  }
}

/// Decodes a blob written by [encodeElements].
///
/// [idFor] mints an id per element; pass a deterministic one in tests.
List<CanvasElement> decodeElements(
  Uint8List bytes, {
  String Function()? idFor,
}) {
  const uuid = Uuid();
  final newId = idFor ?? uuid.v4;
  final input = _ByteReader(bytes);

  final magic = input.uint32();
  if (magic != kElementBlobMagic) {
    throw SkdFormatException(
      'element blob has bad magic 0x${magic.toRadixString(16)}',
    );
  }

  final count = input.uint32();
  final elements = _readElements(input, count, newId);

  if (input.remaining != 0) {
    throw SkdFormatException(
      '${input.remaining} trailing bytes after $count elements',
    );
  }
  return elements;
}

/// Reads [count] elements, then resolves the connector bindings among them.
///
/// Two passes, because a connector may bind to an element that comes after it
/// in z-order — the file is written bottom to top, and nothing says the arrow
/// is above both boxes it joins.
List<CanvasElement> _readElements(
  _ByteReader input,
  int count,
  String Function() newId,
) {
  final elements = <CanvasElement>[];
  final bindings = <int, (int, int)>{};
  final textPaths = <int, int>{};

  for (var i = 0; i < count; i++) {
    final type = input.uint8();
    input.skip(3);

    switch (type) {
      case ElementType.stroke:
        elements.add(_readStroke(input, newId()));
      case ElementType.shape:
        elements.add(_readShape(input, newId()));
      case ElementType.text:
        final (text, pathIndex) = _readText(input, newId());
        if (pathIndex != kNoBinding) textPaths[elements.length] = pathIndex;
        elements.add(text);
      case ElementType.connector:
        final (connector, start, end) = _readConnector(input, newId());
        bindings[elements.length] = (start, end);
        elements.add(connector);
      case ElementType.group:
        elements.add(_readGroup(input, newId));
      default:
        // Bodies are variable-length, so an unknown type makes the rest of the
        // blob unparseable. Rejecting beats guessing.
        throw SkdFormatException('unknown elementType $type at element $i');
    }
  }

  return _resolveBindings(elements, bindings, textPaths);
}

/// Turns the stored indices back into element ids.
///
/// An index that names nothing — out of range, or the connector itself — is a
/// corrupt file. It becomes a free end at the origin rather than a crash: a
/// connector in the wrong place beats refusing to open the drawing.
List<CanvasElement> _resolveBindings(
  List<CanvasElement> elements,
  Map<int, (int, int)> bindings,
  Map<int, int> textPaths,
) {
  if (bindings.isEmpty && textPaths.isEmpty) return elements;

  // A binding is only good if it names another element that can be an anchor.
  // A connector, a text element's own index, or an out-of-range index all read
  // as "no binding" rather than a crash.
  String? idAt(int index, int self) {
    if (index == kNoBinding || index < 0 || index >= elements.length) {
      return null;
    }
    if (index == self) return null;
    if (elements[index] is Connector) return null;
    return elements[index].id;
  }

  for (final entry in bindings.entries) {
    final at = entry.key;
    final connector = elements[at] as Connector;
    final (startIndex, endIndex) = entry.value;

    final startId = idAt(startIndex, at);
    final endId = idAt(endIndex, at);

    elements[at] = connector.copyWith(
      start: startId == null ? connector.start : ConnectorEnd.bound(startId),
      end: endId == null ? connector.end : ConnectorEnd.bound(endId),
    );
  }

  for (final entry in textPaths.entries) {
    final at = entry.key;
    final text = elements[at] as TextElement;
    final pathId = idAt(entry.value, at);
    elements[at] = pathId == null
        ? text.copyWith(clearPath: true)
        : text.copyWith(pathElementId: pathId);
  }
  return elements;
}

void _writeConnector(
  _ByteWriter out,
  Connector connector,
  List<CanvasElement> siblings,
) {
  out
    ..uint8(connector.strokeStyle.value)
    ..uint8(connector.startArrow ? 1 : 0)
    ..uint8(connector.endArrow ? 1 : 0)
    ..reserved(1)
    ..uint32(connector.strokeColorRGBA)
    ..float32(connector.strokeWidth);

  _writeConnectorEnd(out, connector.start, siblings);
  _writeConnectorEnd(out, connector.end, siblings);
}

void _writeConnectorEnd(
  _ByteWriter out,
  ConnectorEnd end,
  List<CanvasElement> siblings,
) {
  if (!end.isBound) {
    out
      ..uint8(ConnectorEndKind.free)
      ..reserved(3)
      ..float32(end.x!)
      ..float32(end.y!)
      ..uint32(kNoBinding);
    return;
  }

  final index = siblings.indexWhere((e) => e.id == end.elementId);
  if (index == -1) {
    // Bound to something that is not a sibling. The model should not allow it;
    // write a free end at the origin rather than a dangling index.
    out
      ..uint8(ConnectorEndKind.free)
      ..reserved(3)
      ..float32(0)
      ..float32(0)
      ..uint32(kNoBinding);
    return;
  }

  out
    ..uint8(ConnectorEndKind.bound)
    ..reserved(3)
    // A bound end has no coordinates of its own; the slots stay, so both kinds
    // of end are the same size and the body's length does not depend on them.
    ..float32(0)
    ..float32(0)
    ..uint32(index);
}

/// Returns the connector with **free** ends, plus the two stored indices.
/// [_resolveBindings] turns those into ids once every sibling has been read.
(Connector, int, int) _readConnector(_ByteReader input, String id) {
  final styleValue = input.uint8();
  final startArrow = input.uint8() != 0;
  final endArrow = input.uint8() != 0;
  input.skip(1);

  final StrokeStyle style;
  try {
    style = StrokeStyle.fromValue(styleValue);
  } on ArgumentError catch (e) {
    throw SkdFormatException('${e.message} ($styleValue)');
  }

  final strokeColorRGBA = input.uint32();
  final strokeWidth = input.float32();

  final (start, startIndex) = _readConnectorEnd(input);
  final (end, endIndex) = _readConnectorEnd(input);

  return (
    Connector(
      id: id,
      start: start,
      end: end,
      strokeColorRGBA: strokeColorRGBA,
      strokeWidth: _positive(strokeWidth, 'connector strokeWidth'),
      strokeStyle: style,
      startArrow: startArrow,
      endArrow: endArrow,
    ),
    startIndex,
    endIndex,
  );
}

(ConnectorEnd, int) _readConnectorEnd(_ByteReader input) {
  final kind = input.uint8();
  input.skip(3);
  final x = input.float32();
  final y = input.float32();
  final index = input.uint32();

  if (kind == ConnectorEndKind.bound) {
    // Placeholder: the caller rebinds it once the siblings are known.
    return (ConnectorEnd.free(x, y), index);
  }
  if (kind != ConnectorEndKind.free) {
    throw SkdFormatException('unknown connector end kind $kind');
  }
  return (ConnectorEnd.free(x, y), kNoBinding);
}

void _writeGroup(_ByteWriter out, Group group) {
  out.uint32(group.children.length);
  for (final child in group.children) {
    // Children bind among themselves, not to the layer around them.
    _writeElement(out, child, group.children);
  }
}

Group _readGroup(_ByteReader input, String Function() newId) {
  final count = input.uint32();
  if (count < 2) {
    throw SkdFormatException('a group holds $count children; two is the least');
  }
  return Group(id: newId(), children: _readElements(input, count, newId));
}

void _writeStroke(_ByteWriter out, Stroke stroke) {
  out
    ..uint32(stroke.colorRGBA)
    ..float32(stroke.baseWidth)
    ..uint8(stroke.toolId)
    ..reserved(3)
    ..uint32(stroke.points.length);
  for (final p in stroke.points) {
    out
      ..float32(p.x)
      ..float32(p.y)
      ..float32(p.pressure);
  }
}

Stroke _readStroke(_ByteReader input, String id) {
  final colorRGBA = input.uint32();
  final baseWidth = input.float32();
  final toolId = input.uint8();
  input.skip(3);
  final count = input.uint32();

  return Stroke(
    id: id,
    colorRGBA: colorRGBA,
    // A zero width would trip the model's assertion; a file claiming one is
    // corrupt, not a document with invisible strokes.
    baseWidth: _positive(baseWidth, 'stroke baseWidth'),
    toolId: toolId,
    points: [
      for (var i = 0; i < count; i++)
        StrokePoint(
          x: input.float32(),
          y: input.float32(),
          pressure: input.float32().clamp(0.0, 1.0),
        ),
    ],
  );
}

void _writeShape(_ByteWriter out, Shape shape) {
  final box = shape.normalized();
  out
    ..uint8(box.type.value)
    ..uint8(box.strokeStyle.value)
    // v2 spends the first of v1's two reserved bytes on the render style. A v1
    // reader ignores reserved bytes, so it draws the shape precisely rather
    // than failing — the drawing is all there, just not wobbly.
    ..uint8(box.renderStyle.value)
    ..reserved(1)
    ..float32(box.x)
    ..float32(box.y)
    ..float32(box.w)
    ..float32(box.h)
    ..float32(box.rotation)
    ..uint32(box.strokeColorRGBA)
    ..uint32(box.fillColorRGBA)
    ..float32(box.strokeWidth)
    ..uint32(box.seed);
}

Shape _readShape(_ByteReader input, String id) {
  final typeValue = input.uint8();
  final styleValue = input.uint8();
  // A v1 file wrote zero here, which is exactly ShapeRenderStyle.precise.
  final renderStyle = ShapeRenderStyle.fromValue(input.uint8());
  input.skip(1);

  final ShapeType type;
  final StrokeStyle style;
  try {
    type = ShapeType.fromValue(typeValue);
    style = StrokeStyle.fromValue(styleValue);
  } on ArgumentError catch (e) {
    throw SkdFormatException('${e.message} ($typeValue/$styleValue)');
  }

  final x = input.float32();
  final y = input.float32();
  final w = input.float32();
  final h = input.float32();
  final rotation = input.float32();
  final strokeColorRGBA = input.uint32();
  final fillColorRGBA = input.uint32();
  final strokeWidth = input.float32();
  final seed = input.uint32();

  return Shape(
    id: id,
    type: type,
    x: x,
    y: y,
    w: w,
    h: h,
    rotation: rotation,
    strokeColorRGBA: strokeColorRGBA,
    fillColorRGBA: fillColorRGBA,
    strokeWidth: _positive(strokeWidth, 'shape strokeWidth'),
    strokeStyle: style,
    renderStyle: renderStyle,
    seed: seed,
  );
}

void _writeText(
  _ByteWriter out,
  TextElement text,
  List<CanvasElement> siblings,
) {
  out
    ..float32(text.x)
    ..float32(text.y)
    ..float32(text.w)
    ..float32(text.h)
    ..float32(text.rotation)
    ..float32(text.fontSize)
    ..uint32(text.colorRGBA)
    ..uint8(text.align.value)
    // The first reserved byte carries the list style; the second a flag byte
    // whose bit 0 says a path-binding index follows the runs. v1/v2/v3 files
    // wrote zeros here, so they read as a plain, unbound text box.
    ..uint8(text.listStyle.value)
    ..uint8(text.isOnPath ? 0x1 : 0)
    ..reserved(1)
    ..lengthPrefixedUtf8(text.fontFamily)
    ..uint32(text.runs.length);

  for (final run in text.runs) {
    out
      ..uint8(run.styleFlags)
      ..reserved(3);
    // Optional per-run size and colour, present only when their flag bit is
    // set (bits 3 and 4). A v1/v2 run set neither bit, so this writes nothing
    // extra for it and the record stays exactly the length it always was.
    if (run.fontSize != null) out.float32(run.fontSize!);
    if (run.colorRGBA != null) out.uint32(run.colorRGBA!);
    out.lengthPrefixedUtf8(run.text);
  }

  // The path-binding index goes last, so a reader that does not know the flag
  // never looks for it. Stored as a sibling index, like a connector end.
  if (text.isOnPath) {
    final index = siblings.indexWhere((e) => e.id == text.pathElementId);
    out.uint32(index == -1 ? kNoBinding : index);
  }
}

(TextElement, int) _readText(_ByteReader input, String id) {
  final x = input.float32();
  final y = input.float32();
  final w = input.float32();
  final h = input.float32();
  final rotation = input.float32();
  final fontSize = input.float32();
  final colorRGBA = input.uint32();
  final alignValue = input.uint8();
  final listStyle = ListStyle.fromValue(input.uint8());
  final textFlags = input.uint8();
  input.skip(1);
  final hasPath = textFlags & 0x1 != 0;

  final TextAlignment align;
  try {
    align = TextAlignment.fromValue(alignValue);
  } on ArgumentError {
    throw SkdFormatException('unknown text alignment $alignValue');
  }

  final family = input.lengthPrefixedUtf8();
  final runCount = input.uint32();
  final runs = <TextRun>[];
  for (var i = 0; i < runCount; i++) {
    final flags = input.uint8();
    input.skip(3);
    // The flag bits are self-describing, so this reads v1/v2 and v3 runs the
    // same way — an old run has bits 3/4 clear and carries no size or colour.
    final fontSize = flags & 0x8 != 0
        ? _positive(input.float32(), 'run fontSize')
        : null;
    final colorRGBA = flags & 0x10 != 0 ? input.uint32() : null;
    runs.add(
      TextRun.fromFlags(
        input.lengthPrefixedUtf8(),
        flags,
        fontSize: fontSize,
        colorRGBA: colorRGBA,
      ),
    );
  }

  // The path index sits after the runs, present only when the flag is set.
  final pathIndex = hasPath ? input.uint32() : kNoBinding;

  return (
    TextElement(
      id: id,
      x: x,
      y: y,
      w: _positive(w, 'text width'),
      h: _positive(h, 'text height'),
      rotation: rotation,
      fontFamily: family,
      fontSize: _positive(fontSize, 'text fontSize'),
      colorRGBA: colorRGBA,
      align: align,
      listStyle: listStyle,
      // Rebound to an id in the resolution pass; a placeholder until then.
      // Readers tolerate a file whose runs are unmerged or empty; the model
      // normalizes them.
      runs: runs,
    ),
    pathIndex,
  );
}

double _positive(double value, String what) {
  if (!value.isFinite || value <= 0) {
    throw SkdFormatException('$what must be positive, got $value');
  }
  return value;
}

/// Little-endian, growable.
class _ByteWriter {
  final BytesBuilder _builder = BytesBuilder(copy: false);
  final ByteData _scratch = ByteData(4);

  void uint8(int value) => _builder.addByte(value & 0xFF);

  void reserved(int count) {
    for (var i = 0; i < count; i++) {
      _builder.addByte(0);
    }
  }

  void uint32(int value) {
    _scratch.setUint32(0, value & 0xFFFFFFFF, Endian.little);
    _builder.add(_scratch.buffer.asUint8List(0, 4).sublist(0));
  }

  void float32(double value) {
    _scratch.setFloat32(0, value, Endian.little);
    _builder.add(_scratch.buffer.asUint8List(0, 4).sublist(0));
  }

  void lengthPrefixedUtf8(String value) {
    final bytes = utf8.encode(value);
    uint32(bytes.length);
    _builder.add(bytes);
  }

  Uint8List takeBytes() => _builder.takeBytes();
}

/// Little-endian, bounds-checked: a truncated file throws rather than reading
/// whatever happens to follow in memory.
class _ByteReader {
  _ByteReader(this._bytes)
    : _data = ByteData.view(_bytes.buffer, _bytes.offsetInBytes, _bytes.length);

  final Uint8List _bytes;
  final ByteData _data;
  int _offset = 0;

  int get remaining => _bytes.length - _offset;

  void _need(int count) {
    if (remaining < count) {
      throw SkdFormatException(
        'element blob truncated: wanted $count more bytes, have $remaining',
      );
    }
  }

  void skip(int count) {
    _need(count);
    _offset += count;
  }

  int uint8() {
    _need(1);
    return _data.getUint8(_offset++);
  }

  int uint32() {
    _need(4);
    final value = _data.getUint32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  double float32() {
    _need(4);
    final value = _data.getFloat32(_offset, Endian.little);
    _offset += 4;
    return value;
  }

  String lengthPrefixedUtf8() {
    final length = uint32();
    _need(length);
    final value = utf8.decode(
      _bytes.sublist(_offset, _offset + length),
      allowMalformed: true,
    );
    _offset += length;
    return value;
  }
}
