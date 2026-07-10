import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/renderer/document_painter.dart';

/// The scales File → Export offers.
const List<int> kExportScales = [1, 2, 4];

/// The largest edge a single export may have, in pixels.
///
/// A 4x export of an 8192px canvas is 32768px on a side, and a 32-bit surface
/// that size is four gigabytes. Refuse it with a reason rather than dying.
const int kMaxExportEdge = 16384;

/// Thrown when the requested export cannot be rendered.
class ExportException implements Exception {
  const ExportException(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// Margin, in document pixels, around an infinite document's content when it
/// is exported — a drawing should not be cropped hard to its ink.
const double kInfiniteExportMargin = 32;

/// The document-space region an export covers: the page for a bounded document,
/// the content (plus a margin) for an infinite one.
///
/// An infinite document with nothing in it exports a small blank tile rather
/// than a zero-size image.
Bounds exportRegion(SkdDocument document) {
  if (!document.isInfinite) {
    return Bounds(
      left: 0,
      top: 0,
      right: document.canvasWidth.toDouble(),
      bottom: document.canvasHeight.toDouble(),
    );
  }
  final content = document.bounds;
  if (content == null) {
    return const Bounds(left: 0, top: 0, right: 256, bottom: 256);
  }
  return content.inflate(kInfiniteExportMargin);
}

/// The pixel size of [document] exported at [scale].
({int width, int height}) exportSizeFor(SkdDocument document, int scale) {
  final region = exportRegion(document);
  return (
    width: math.max(1, (region.width * scale).round()),
    height: math.max(1, (region.height * scale).round()),
  );
}

/// Renders the flattened document to PNG bytes at [scale].
///
/// With [transparentBackground] the document's background fill is skipped, so
/// the page is see-through wherever nothing was drawn. Layer visibility,
/// opacity and blend modes are honoured — this is the same painter the canvas
/// uses, at a different scale, so what is exported is what was on screen.
///
/// Text renders with the machine's fonts, so these bytes are not reproducible
/// across platforms. Never assert them against a golden.
Future<Uint8List> renderDocumentPng(
  SkdDocument document, {
  int scale = 1,
  bool transparentBackground = false,
}) async {
  if (scale < 1) {
    throw ExportException('an export scale must be at least 1 (got $scale)');
  }
  final size = exportSizeFor(document, scale);
  if (size.width > kMaxExportEdge || size.height > kMaxExportEdge) {
    throw ExportException(
      '${size.width} × ${size.height} is larger than this build can render '
      '(limit $kMaxExportEdge on a side). Try a smaller scale.',
    );
  }

  final width = size.width.toDouble();
  final height = size.height.toDouble();
  final region = exportRegion(document);

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (!transparentBackground) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = colorFromRGBA(document.backgroundRGBA),
    );
  }

  // The region's top-left maps to the image origin; for a bounded page that is
  // document (0, 0), for an infinite one it is the content's corner.
  canvas.translate(-region.left * scale, -region.top * scale);

  DocumentPainter(
    document: document,
    scale: scale.toDouble(),
  ).paint(canvas, Size(width, height));

  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width, size.height);
  picture.dispose();

  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) throw const ExportException('failed to encode the PNG');
  return data.buffer.asUint8List();
}
