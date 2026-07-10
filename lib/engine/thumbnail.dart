import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/renderer/document_painter.dart';

/// Longest edge of the `thumbnail.png` stored in a `.skd`.
const int kThumbnailMaxSize = 256;

/// The thumbnail's pixel size for a document, longest edge [maxSize],
/// preserving aspect and never upscaling past 1:1.
({int width, int height}) thumbnailSizeFor(
  int documentWidth,
  int documentHeight, {
  int maxSize = kThumbnailMaxSize,
}) {
  final scale = math
      .min(maxSize / documentWidth, maxSize / documentHeight)
      .clamp(0.0, 1.0);
  return (
    width: math.max(1, (documentWidth * scale).round()),
    height: math.max(1, (documentHeight * scale).round()),
  );
}

/// Renders the flattened document to a PNG for the archive's `thumbnail.png`.
///
/// Lives in `engine/`, not `format/`: rasterizing needs `dart:ui`, and
/// `format/` stays Flutter-free so it is testable without a widget harness.
/// The writer just takes the bytes.
///
/// Text renders with whatever fonts the machine has, so these bytes are **not**
/// reproducible across platforms. Never assert them against a golden.
Future<Uint8List> renderThumbnailPng(
  SkdDocument document, {
  int maxSize = kThumbnailMaxSize,
}) async {
  final size = thumbnailSizeFor(
    document.canvasWidth,
    document.canvasHeight,
    maxSize: maxSize,
  );
  final scale = size.width / document.canvasWidth;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(
      Rect.fromLTWH(0, 0, size.width.toDouble(), size.height.toDouble()),
      Paint()..color = colorFromRGBA(document.backgroundRGBA),
    );

  DocumentPainter(
    document: document,
    scale: scale,
  ).paint(canvas, Size(size.width.toDouble(), size.height.toDouble()));

  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width, size.height);
  picture.dispose();

  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) {
    throw StateError('failed to encode the thumbnail as PNG');
  }
  return data.buffer.asUint8List();
}
