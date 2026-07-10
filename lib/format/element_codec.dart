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
}

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
        _writeText(out, element);
    }
  }
  return out.takeBytes();
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
  final elements = <CanvasElement>[];
  for (var i = 0; i < count; i++) {
    final type = input.uint8();
    input.skip(3);

    switch (type) {
      case ElementType.stroke:
        elements.add(_readStroke(input, newId()));
      case ElementType.shape:
        elements.add(_readShape(input, newId()));
      case ElementType.text:
        elements.add(_readText(input, newId()));
      default:
        // Bodies are variable-length, so an unknown type makes the rest of the
        // blob unparseable. Rejecting beats guessing.
        throw SkdFormatException('unknown elementType $type at element $i');
    }
  }

  if (input.remaining != 0) {
    throw SkdFormatException(
      '${input.remaining} trailing bytes after $count elements',
    );
  }
  return elements;
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
    ..reserved(2)
    ..float32(box.x)
    ..float32(box.y)
    ..float32(box.w)
    ..float32(box.h)
    ..float32(box.rotation)
    ..uint32(box.strokeColorRGBA)
    ..uint32(box.fillColorRGBA)
    ..float32(box.strokeWidth)
    ..uint32(0); // seed, reserved for rough rendering
}

Shape _readShape(_ByteReader input, String id) {
  final typeValue = input.uint8();
  final styleValue = input.uint8();
  input.skip(2);

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
  input.uint32(); // seed

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
  );
}

void _writeText(_ByteWriter out, TextElement text) {
  out
    ..float32(text.x)
    ..float32(text.y)
    ..float32(text.w)
    ..float32(text.h)
    ..float32(text.rotation)
    ..float32(text.fontSize)
    ..uint32(text.colorRGBA)
    ..uint8(text.align.value)
    ..reserved(3)
    ..lengthPrefixedUtf8(text.fontFamily)
    ..uint32(text.runs.length);

  for (final run in text.runs) {
    out
      ..uint8(run.styleFlags)
      ..reserved(3)
      ..lengthPrefixedUtf8(run.text);
  }
}

TextElement _readText(_ByteReader input, String id) {
  final x = input.float32();
  final y = input.float32();
  final w = input.float32();
  final h = input.float32();
  final rotation = input.float32();
  final fontSize = input.float32();
  final colorRGBA = input.uint32();
  final alignValue = input.uint8();
  input.skip(3);

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
    runs.add(TextRun.fromFlags(input.lengthPrefixedUtf8(), flags));
  }

  return TextElement(
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
    // Readers tolerate a file whose runs are unmerged or empty; the model
    // normalizes them.
    runs: runs,
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
