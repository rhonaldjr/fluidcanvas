import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/shape_paths.dart';
import 'package:inkpad/engine/text_layout.dart';

/// The outline a text element may flow its glyphs along, in document space, or
/// null when [element] is not something text can attach to.
///
/// A shape gives its rotated outline, a connector its resolved line, a stroke
/// its centreline. A group or another text element has no single outline, so
/// binding to one is refused at the command level and null here is the backstop.
ui.Path? outlinePathFor(CanvasElement element, List<CanvasElement> siblings) {
  switch (element) {
    case Shape():
      final box = element.normalized();
      final rect = Rect.fromLTWH(box.x, box.y, box.w, box.h);
      final path = buildShapePath(box.type, rect, strokeWidth: box.strokeWidth);
      if (!box.isRotated) return path;
      final matrix = Matrix4.identity()
        ..translateByDouble(box.centerX, box.centerY, 0, 1)
        ..rotateZ(box.rotation)
        ..translateByDouble(-box.centerX, -box.centerY, 0, 1);
      return path.transform(matrix.storage);
    case Connector():
      final line = resolveConnector(element, siblings);
      return ui.Path()
        ..moveTo(line.x1, line.y1)
        ..lineTo(line.x2, line.y2);
    case Stroke():
      if (element.points.length < 2) return null;
      final path = ui.Path()
        ..moveTo(element.points.first.x, element.points.first.y);
      for (final p in element.points.skip(1)) {
        path.lineTo(p.x, p.y);
      }
      return path;
    case TextElement():
    case Group():
      return null;
  }
}

/// One glyph and the style it is drawn in, taken from the runs.
typedef _Glyph = ({String char, TextStyle style});

/// The glyphs of [element], each carrying its run's resolved style.
///
/// Newlines make no sense along a path, so they read as spaces.
List<_Glyph> _glyphs(TextElement element) {
  final base = Color.fromARGB(
    element.colorRGBA & 0xFF,
    (element.colorRGBA >> 24) & 0xFF,
    (element.colorRGBA >> 16) & 0xFF,
    (element.colorRGBA >> 8) & 0xFF,
  );
  final glyphs = <_Glyph>[];
  for (final run in element.runs) {
    final style = runStyle(
      run,
      fontSize: run.fontSize ?? element.fontSize,
      fontFamily: element.fontFamily,
      color: base,
    );
    for (final char in run.text.replaceAll('\n', ' ').characters) {
      glyphs.add((char: char, style: style));
    }
  }
  return glyphs;
}

/// Draws [element]'s glyphs one by one along [path], each rotated to the path's
/// tangent, until the path runs out.
///
/// Not wrapped and not shrunk to fit: path text flows at its font size and
/// stops where the path ends. What does not fit simply is not drawn — the box's
/// height means nothing here.
void paintTextOnPath(ui.Canvas canvas, TextElement element, ui.Path path) {
  final metrics = path.computeMetrics().toList();
  if (metrics.isEmpty || element.isEmpty) return;

  var metricIndex = 0;
  var distance = 0.0;

  for (final glyph in _glyphs(element)) {
    final painter = TextPainter(
      text: TextSpan(text: glyph.char, style: glyph.style),
      textDirection: TextDirection.ltr,
    )..layout();
    final advance = painter.width;

    // Step to the next subpath when this one is used up (a rectangle outline is
    // four subpaths; text should carry on around the corner).
    while (distance + advance > metrics[metricIndex].length) {
      metricIndex++;
      distance = 0;
      if (metricIndex >= metrics.length) {
        painter.dispose();
        return;
      }
    }

    final tangent = metrics[metricIndex].getTangentForOffset(
      distance + advance / 2,
    );
    if (tangent != null) {
      final baseline = painter.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      canvas
        ..save()
        ..translate(tangent.position.dx, tangent.position.dy)
        ..rotate(tangent.angle)
        // Centre the glyph on the tangent point, its baseline on the path.
        ..translate(-advance / 2, -baseline);
      painter.paint(canvas, Offset.zero);
      canvas.restore();
    }

    distance += advance;
    painter.dispose();
  }
}

/// The box around path-bound [element], in document space, or null when its
/// path cannot be resolved.
Bounds? textOnPathBounds(TextElement element, List<CanvasElement> siblings) {
  final id = element.pathElementId;
  if (id == null) return null;
  final target = siblings.firstWhere((e) => e.id == id, orElse: () => element);
  if (identical(target, element)) return null;
  final box = target.bounds;
  if (box == null) return null;
  // The glyphs sit within a font height of the outline; pad by that.
  return box.inflate(element.fontSize);
}

/// Whether ([x], [y]) lands on path-bound [element]'s glyphs, tested as
/// proximity to the outline it flows along.
bool hitTextOnPath(
  TextElement element,
  double x,
  double y,
  double tolerance,
  List<CanvasElement> siblings,
) {
  final id = element.pathElementId;
  if (id == null) return false;
  final target = siblings.firstWhere((e) => e.id == id, orElse: () => element);
  if (identical(target, element)) return false;

  final path = outlinePathFor(target, siblings);
  if (path == null) return false;

  final reach = tolerance + element.fontSize;
  for (final metric in path.computeMetrics()) {
    // Sample the path and test distance; cheap and good enough for a label.
    final steps = math.max(2, (metric.length / 8).ceil());
    for (var i = 0; i <= steps; i++) {
      final t = metric.getTangentForOffset(metric.length * i / steps);
      if (t == null) continue;
      final dx = t.position.dx - x;
      final dy = t.position.dy - y;
      if (dx * dx + dy * dy <= reach * reach) return true;
    }
  }
  return false;
}
