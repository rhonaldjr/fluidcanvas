import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:inkpad/domain/models/models.dart';

/// The text never shrinks below this fraction of its font size.
///
/// Past it, a box scaled to 3% is worse than an honest overflow: the user
/// cannot read what they typed, and cannot see that anything is wrong.
const double kMinTextFitScale = 0.25;

/// How many halvings the fit search does. Fixed, so the answer is deterministic
/// and cheap rather than "whatever converged".
const int kFitSearchSteps = 12;

/// A laid-out text box.
class TextLayout {
  const TextLayout({
    required this.paragraph,
    required this.fitScale,
    required this.overflows,
  });

  /// Laid out to the box's width, already at [fitScale].
  final ui.Paragraph paragraph;

  /// The factor the font size was multiplied by so the text fits the box.
  /// 1 when it already fitted.
  final double fitScale;

  /// Whether the text still does not fit at [kMinTextFitScale].
  final bool overflows;

  double get height => paragraph.height;
}

/// The marker prefixed to line [lineIndex] (0-based) for [style], or empty for
/// [ListStyle.none]. Numbered lists count from 1.
String listMarker(ListStyle style, int lineIndex) => switch (style) {
  ListStyle.none => '',
  ListStyle.bullet => '•  ',
  ListStyle.numbered => '${lineIndex + 1}.  ',
};

/// Maps a [TextAlignment] onto Flutter's.
TextAlign flutterAlign(TextAlignment align) => switch (align) {
  TextAlignment.left => TextAlign.left,
  TextAlignment.center => TextAlign.center,
  TextAlignment.right => TextAlign.right,
};

/// Unpacks a 0xRRGGBBAA int into a Flutter [Color] (ARGB).
Color _color(int rgba) => Color.fromARGB(
  rgba & 0xFF,
  (rgba >> 24) & 0xFF,
  (rgba >> 16) & 0xFF,
  (rgba >> 8) & 0xFF,
);

/// The style one run is drawn with, at [fontSize].
///
/// A run's own [TextRun.fontSize] and [TextRun.colorRGBA] override the
/// element's when set. The size passed in has already been through the
/// shrink-to-fit scale, so per-run sizes scale with the box like the rest.
TextStyle runStyle(
  TextRun run, {
  required double fontSize,
  required String fontFamily,
  required Color color,
}) => TextStyle(
  color: run.colorRGBA == null ? color : _color(run.colorRGBA!),
  fontFamily: fontFamily.isEmpty ? null : fontFamily,
  fontSize: fontSize,
  fontWeight: run.bold ? FontWeight.bold : FontWeight.normal,
  fontStyle: run.italic ? FontStyle.italic : FontStyle.normal,
  decoration: run.underline ? TextDecoration.underline : TextDecoration.none,
);

/// Builds a paragraph for [element] at [fontSize], wrapped to its box width.
ui.Paragraph buildParagraph(TextElement element, double fontSize) {
  final color = Color.fromARGB(
    element.colorRGBA & 0xFF,
    (element.colorRGBA >> 24) & 0xFF,
    (element.colorRGBA >> 16) & 0xFF,
    (element.colorRGBA >> 8) & 0xFF,
  );

  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(
      textAlign: flutterAlign(element.align),
      fontFamily: element.fontFamily.isEmpty ? null : element.fontFamily,
      fontSize: fontSize,
    ),
  );

  // The scale the box has been shrunk by; a per-run size rides it too, so a
  // 40pt run in a 24pt box stays proportionally larger as the box shrinks.
  final scale = element.fontSize == 0 ? 1.0 : fontSize / element.fontSize;
  final baseStyle = runStyle(
    const TextRun(''),
    fontSize: fontSize,
    fontFamily: element.fontFamily,
    color: color,
  ).getTextStyle();

  var lineIndex = 0;
  var atLineStart = true;

  void emitMarker() {
    final marker = listMarker(element.listStyle, lineIndex);
    if (marker.isEmpty) return;
    builder
      ..pushStyle(baseStyle)
      ..addText(marker)
      ..pop();
  }

  for (final run in element.runs) {
    final runTextStyle = runStyle(
      run,
      fontSize: (run.fontSize ?? element.fontSize) * scale,
      fontFamily: element.fontFamily,
      color: color,
    ).getTextStyle();

    // Split on newlines so a list marker can be dropped in at each line start.
    final parts = run.text.split('\n');
    for (var j = 0; j < parts.length; j++) {
      if (atLineStart) {
        emitMarker();
        atLineStart = false;
      }
      if (parts[j].isNotEmpty) {
        builder
          ..pushStyle(runTextStyle)
          ..addText(parts[j])
          ..pop();
      }
      if (j < parts.length - 1) {
        builder
          ..pushStyle(baseStyle)
          ..addText('\n')
          ..pop();
        lineIndex++;
        atLineStart = true;
      }
    }
  }

  return builder.build()..layout(ui.ParagraphConstraints(width: element.w));
}

/// Lays out [element], shrinking the font until the wrapped text fits its box.
///
/// Binary search over the scale, [kFitSearchSteps] halvings. Monotonic: a
/// smaller font never makes the text taller, which is what makes the search
/// valid.
TextLayout layoutText(TextElement element) {
  final full = buildParagraph(element, element.fontSize);
  if (full.height <= element.h || element.isEmpty) {
    return TextLayout(paragraph: full, fitScale: 1, overflows: false);
  }

  final floor = buildParagraph(element, element.fontSize * kMinTextFitScale);
  if (floor.height > element.h) {
    // Even at the floor it does not fit. Show it anyway, and say so.
    return TextLayout(
      paragraph: floor,
      fitScale: kMinTextFitScale,
      overflows: true,
    );
  }

  var low = kMinTextFitScale;
  var high = 1.0;
  var best = floor;
  var bestScale = kMinTextFitScale;

  for (var i = 0; i < kFitSearchSteps; i++) {
    final mid = (low + high) / 2;
    final candidate = buildParagraph(element, element.fontSize * mid);
    if (candidate.height <= element.h) {
      best = candidate;
      bestScale = mid;
      low = mid;
    } else {
      high = mid;
    }
  }

  return TextLayout(paragraph: best, fitScale: bestScale, overflows: false);
}

/// The character offset nearest [local], a point inside the box.
int offsetForPosition(TextLayout layout, Offset local) =>
    layout.paragraph.getPositionForOffset(local).offset;

/// The caret rectangle for [offset], in box-local coordinates.
Rect caretRect(TextLayout layout, int offset, double fontSize) {
  final boxes = layout.paragraph.getBoxesForRange(
    math.max(0, offset - 1),
    offset,
  );
  if (boxes.isEmpty) {
    return Rect.fromLTWH(0, 0, 1, fontSize * layout.fitScale);
  }
  final box = boxes.last;
  return Rect.fromLTRB(box.right, box.top, box.right + 1, box.bottom);
}
