import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/format/skd_exception.dart';

/// Where a layer's element blob lives inside the archive.
String elementFileFor(String layerId) => 'elements/$layerId.bin';

/// `document.json` — the document's structure, without its element geometry.
///
/// The elements live in the per-layer binary blobs; this only names them.
Map<String, dynamic> documentToJson(SkdDocument document) => {
  'canvas': {
    'width': document.canvasWidth,
    'height': document.canvasHeight,
    'background': rgbToHex(document.backgroundRGBA),
    // Omitted for a bounded document, so v3 files that predate infinite mode
    // and every re-saved older file stay byte-for-byte as they were.
    if (document.isInfinite) 'mode': document.canvasMode.value,
  },
  'layers': [
    for (final layer in document.layers)
      {
        'id': layer.id,
        'name': layer.name,
        'visible': layer.visible,
        'opacity': layer.opacity,
        'blendMode': layer.blendMode.wireName,
        'elementFile': elementFileFor(layer.id),
      },
  ],
};

/// Rebuilds a document from `document.json` plus the decoded element blobs.
///
/// [elementsFor] is handed each layer id and returns that layer's elements.
SkdDocument documentFromJson(
  Map<String, dynamic> json,
  List<CanvasElement> Function(String layerId) elementsFor,
) {
  final canvas = _require<Map<String, dynamic>>(json, 'canvas');
  final width = _requireInt(canvas, 'width');
  final height = _requireInt(canvas, 'height');
  if (width <= 0 || height <= 0) {
    throw SkdFormatException('canvas must be positive, got ${width}x$height');
  }

  final rawLayers = _require<List<dynamic>>(json, 'layers');
  if (rawLayers.isEmpty) {
    throw const SkdFormatException('a document must have at least one layer');
  }

  final layers = <Layer>[];
  final seen = <String>{};
  for (final raw in rawLayers) {
    if (raw is! Map<String, dynamic>) {
      throw const SkdFormatException('a layer entry is not an object');
    }
    final id = _require<String>(raw, 'id');
    if (!seen.add(id)) {
      throw SkdFormatException('duplicate layer id "$id"');
    }

    final opacity = (raw['opacity'] as num?)?.toDouble() ?? 1.0;
    layers.add(
      Layer(
        id: id,
        name: _require<String>(raw, 'name'),
        visible: raw['visible'] as bool? ?? true,
        // Clamp rather than throw: a file that says 1.0000001 is not corrupt.
        opacity: opacity.clamp(0.0, 1.0),
        // An unknown blend mode falls back to normal, so a document written by
        // a future version still opens. An unknown *shape* is rejected instead:
        // there is no safe default for geometry.
        blendMode: LayerBlendMode.fromWireName(
          raw['blendMode'] as String? ?? 'normal',
        ),
        elements: elementsFor(id),
      ),
    );
  }

  return SkdDocument(
    canvasWidth: width,
    canvasHeight: height,
    backgroundRGBA: hexToRgb(canvas['background'] as String? ?? '#FFFFFF'),
    // A missing key, an older file, or an unknown value all read as bounded.
    canvasMode: CanvasMode.fromValue(canvas['mode'] as String?),
    layers: layers,
  );
}

/// `0xRRGGBBAA` to `#RRGGBB`. The alpha byte lives only in memory.
String rgbToHex(int rgba) {
  final rgb = (rgba >> 8) & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// `#RRGGBB` to `0xRRGGBBAA`, opaque. Anything unparseable becomes white,
/// because a background colour is never worth refusing to open a file over.
int hexToRgb(String hex) {
  final cleaned = hex.startsWith('#') ? hex.substring(1) : hex;
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null || cleaned.length != 6) {
    return 0xFFFFFFFF;
  }
  return (value << 8) | 0xFF;
}

T _require<T>(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! T) {
    throw SkdFormatException('document.json is missing "$key"');
  }
  return value;
}

int _requireInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! num) {
    throw SkdFormatException('document.json is missing "$key"');
  }
  return value.toInt();
}
