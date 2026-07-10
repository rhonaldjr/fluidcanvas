import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/renderer/variable_width.dart';
import 'package:inkpad/engine/rough.dart' show roughNoise;

/// A brush's seed, derived from the stroke's own geometry.
///
/// Strokes carry no seed field — adding one would be a format change — so the
/// texture and pencil grain hash the points instead. Points are stored as
/// exact float32, so the same stroke seeds identically on every machine and
/// after every reload, and no two differently-shaped strokes share a grain.
int brushSeed(Stroke stroke) {
  var hash = 0x811C9DC5 ^ stroke.points.length;
  for (final point in stroke.points) {
    hash = (hash ^ point.x.toRawInt()) * 0x01000193 & 0xFFFFFFFF;
    hash = (hash ^ point.y.toRawInt()) * 0x01000193 & 0xFFFFFFFF;
  }
  return hash & 0xFFFFFFFF;
}

extension on double {
  /// The low 32 bits of this double's IEEE-754 bit pattern.
  int toRawInt() {
    final bytes = ByteData(8)..setFloat64(0, this);
    return bytes.getUint32(4);
  }
}

/// Points resampled to a fixed [spacing] by arc length, each carrying the
/// pressure interpolated from the original samples.
///
/// A brush that stamps dabs needs even spacing, or a fast drag would scatter
/// them and a slow one would pile them up. The centreline is walked, not the
/// raw input.
List<StrokePoint> resampleByArcLength(
  List<StrokePoint> points,
  double spacing,
) {
  if (points.length < 2 || spacing <= 0) return points;

  final out = <StrokePoint>[points.first];
  var carried = 0.0;

  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1];
    final b = points[i];
    final segment = math.sqrt(
      (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y),
    );
    if (segment < 1e-9) continue;

    var travelled = spacing - carried;
    while (travelled <= segment) {
      final t = travelled / segment;
      out.add(
        StrokePoint(
          x: a.x + (b.x - a.x) * t,
          y: a.y + (b.y - a.y) * t,
          pressure: a.pressure + (b.pressure - a.pressure) * t,
        ),
      );
      travelled += spacing;
    }
    carried = segment - (travelled - spacing);
  }
  return out;
}

/// The dabs a **texture** stroke stamps: small seeded-jittered ovals along the
/// centreline, with gaps between them that read as a dry, textured brush.
///
/// A pure path, so it is deterministic and testable — the same stroke stamps
/// the same dabs on every repaint.
Path buildTextureStamps(Stroke stroke, {int? seed}) {
  final path = Path();
  final points = stroke.points;
  if (points.isEmpty) return path;

  final s = seed ?? brushSeed(stroke);
  final spacing = math.max(1.0, stroke.baseWidth * 0.55);
  final dabs = resampleByArcLength(points, spacing);

  for (var i = 0; i < dabs.length; i++) {
    final half = widthForPressure(stroke.baseWidth, dabs[i].pressure) / 2;
    // Each dab wanders a little and varies in size, so the edge is broken.
    final jx = roughNoise(s, i * 2) * half * 0.5;
    final jy = roughNoise(s, i * 2 + 1) * half * 0.5;
    final r = half * (0.6 + 0.4 * (roughNoise(s, i * 3 + 7) + 1) / 2);
    path.addOval(
      Rect.fromCircle(
        center: Offset(dabs[i].x + jx, dabs[i].y + jy),
        radius: r,
      ),
    );
  }
  return path;
}

/// The grain a **pencil** stroke scatters over its fill: short seeded flecks
/// that give the solid shape a graphite tooth.
Path buildPencilGrain(Stroke stroke, {int? seed}) {
  final path = Path();
  final points = stroke.points;
  if (points.length < 2) return path;

  final s = seed ?? brushSeed(stroke);
  final spacing = math.max(0.8, stroke.baseWidth * 0.4);
  final flecks = resampleByArcLength(points, spacing);

  for (var i = 1; i < flecks.length; i++) {
    final half = widthForPressure(stroke.baseWidth, flecks[i].pressure) / 2;
    // A fleck sits somewhere across the stroke's width, along its direction.
    final dx = flecks[i].x - flecks[i - 1].x;
    final dy = flecks[i].y - flecks[i - 1].y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) continue;
    final nx = -dy / len;
    final ny = dx / len;

    final across = roughNoise(s, i) * half;
    final cx = flecks[i].x + nx * across;
    final cy = flecks[i].y + ny * across;
    final flen = half * (0.4 + 0.4 * (roughNoise(s, i * 5 + 3) + 1) / 2);

    path
      ..moveTo(cx - (dx / len) * flen, cy - (dy / len) * flen)
      ..lineTo(cx + (dx / len) * flen, cy + (dy / len) * flen);
  }
  return path;
}
