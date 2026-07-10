import 'package:flutter/material.dart';
import 'package:inkpad/engine/snapping.dart';

/// The grid under the page, and the alignment guides over it.
///
/// Both are *view* decoration: they live in no document, are never exported,
/// and never appear in a `.skd`. The grid is drawn beneath the drawing, the
/// guides above it.
class GridPainter extends CustomPainter {
  const GridPainter({
    required this.gridSize,
    required this.scale,
    required this.color,
  });

  /// In document pixels.
  final double gridSize;

  /// Page screen size divided by document size.
  final double scale;

  final Color color;

  /// Below this many screen pixels apart, a grid is a grey wash. Stop drawing
  /// it rather than painting a thousand invisible lines.
  static const double minScreenSpacing = 4;

  @override
  void paint(Canvas canvas, Size size) {
    if (scale <= 0 || gridSize <= 0) return;
    final spacing = gridSize * scale;
    if (spacing < minScreenSpacing) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    for (var x = spacing; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = spacing; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(GridPainter old) =>
      old.gridSize != gridSize || old.scale != scale || old.color != color;
}

/// The lines showing what the dragged element is currently aligned with.
class GuidesPainter extends CustomPainter {
  const GuidesPainter({
    required this.guides,
    required this.scale,
    required this.color,
  });

  final List<SnapGuide> guides;
  final double scale;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (scale <= 0 || guides.isEmpty) return;

    canvas.save();
    canvas.scale(scale);

    final paint = Paint()
      ..color = color
      // One screen pixel however far the page is zoomed.
      ..strokeWidth = 1 / scale;

    for (final guide in guides) {
      final from = guide.vertical
          ? Offset(guide.position, guide.start)
          : Offset(guide.start, guide.position);
      final to = guide.vertical
          ? Offset(guide.position, guide.end)
          : Offset(guide.end, guide.position);
      canvas.drawLine(from, to, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(GuidesPainter old) =>
      old.scale != scale || old.color != color || !_same(old.guides, guides);

  static bool _same(List<SnapGuide> a, List<SnapGuide> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
