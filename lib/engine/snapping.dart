import 'dart:math' as math;

import 'package:inkpad/domain/models/models.dart';

/// How close, in **screen** pixels, an edge must come before it snaps.
///
/// Screen, not document: a snap should feel the same at 10% and at 800% zoom.
/// Callers divide by the page scale before calling in.
const double kSnapThreshold = 6;

/// The grid new documents use, in document pixels.
const double kDefaultGridSize = 20;

/// A line to draw while a snap is active, in document space.
///
/// Vertical guides have a constant [position] in x; horizontal ones in y. The
/// span is the union of the moving box and whatever it snapped to, so the guide
/// visibly connects the two rather than crossing the whole page.
class SnapGuide {
  const SnapGuide({
    required this.vertical,
    required this.position,
    required this.start,
    required this.end,
  });

  final bool vertical;
  final double position;
  final double start;
  final double end;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SnapGuide &&
          vertical == other.vertical &&
          position == other.position &&
          start == other.start &&
          end == other.end;

  @override
  int get hashCode => Object.hash(vertical, position, start, end);

  @override
  String toString() =>
      'SnapGuide(${vertical ? 'x' : 'y'}=$position, $start..$end)';
}

/// What a snap decided: how far to nudge the drag, and what to draw.
typedef SnapResult = ({double dx, double dy, List<SnapGuide> guides});

const SnapResult kNoSnap = (dx: 0, dy: 0, guides: <SnapGuide>[]);

/// The three x positions and three y positions a box offers to snap against.
List<double> _verticals(Bounds b) => [b.left, b.centerX, b.right];
List<double> _horizontals(Bounds b) => [b.top, b.centerY, b.bottom];

/// The nudge that best aligns [moving] with [targets] and, optionally, a grid.
///
/// Each axis is decided independently and by the *nearest* candidate, so a box
/// can snap its left edge to one element and its top to another. [threshold] is
/// in document pixels — divide the screen threshold by the page scale.
///
/// Element alignment wins over the grid at equal distance: a user who lined a
/// box up against another box meant that, not the grid underneath it.
SnapResult snapBounds({
  required Bounds moving,
  required List<Bounds> targets,
  required double threshold,
  double? gridSize,
}) {
  if (threshold <= 0) return kNoSnap;

  _Best bestX = const _Best();
  _Best bestY = const _Best();

  for (final target in targets) {
    for (final from in _verticals(moving)) {
      for (final to in _verticals(target)) {
        bestX = bestX.consider(to - from, to, target);
      }
    }
    for (final from in _horizontals(moving)) {
      for (final to in _horizontals(target)) {
        bestY = bestY.consider(to - from, to, target);
      }
    }
  }

  if (gridSize != null && gridSize > 0) {
    // Only the box's own edges snap to the grid; its centre landing on a grid
    // line is a coincidence nobody asked for.
    for (final from in [moving.left, moving.right]) {
      bestX = bestX.consider(_toGrid(from, gridSize) - from, null, null);
    }
    for (final from in [moving.top, moving.bottom]) {
      bestY = bestY.consider(_toGrid(from, gridSize) - from, null, null);
    }
  }

  final dx = bestX.within(threshold) ? bestX.delta : 0.0;
  final dy = bestY.within(threshold) ? bestY.delta : 0.0;

  final guides = <SnapGuide>[
    if (bestX.within(threshold) && bestX.line != null)
      _guide(true, bestX.line!, moving.translated(dx, dy), bestX.target!),
    if (bestY.within(threshold) && bestY.line != null)
      _guide(false, bestY.line!, moving.translated(dx, dy), bestY.target!),
  ];

  return (dx: dx, dy: dy, guides: guides);
}

/// The nearest multiple of [grid] to [value].
double _toGrid(double value, double grid) =>
    (value / grid).roundToDouble() * grid;

/// Snaps a single point — what a connector endpoint or a shape-drag corner
/// needs, having no box of its own yet.
SnapResult snapPoint({
  required double x,
  required double y,
  required List<Bounds> targets,
  required double threshold,
  double? gridSize,
}) => snapBounds(
  moving: Bounds(left: x, top: y, right: x, bottom: y),
  targets: targets,
  threshold: threshold,
  gridSize: gridSize,
);

SnapGuide _guide(bool vertical, double position, Bounds moved, Bounds target) {
  final a = vertical ? moved.top : moved.left;
  final b = vertical ? moved.bottom : moved.right;
  final c = vertical ? target.top : target.left;
  final d = vertical ? target.bottom : target.right;

  return SnapGuide(
    vertical: vertical,
    position: position,
    start: math.min(math.min(a, b), math.min(c, d)),
    end: math.max(math.max(a, b), math.max(c, d)),
  );
}

/// The closest candidate seen so far on one axis.
class _Best {
  const _Best([this.delta = 0, this.line, this.target, this.seen = false]);

  final double delta;

  /// Where the guide goes, or `null` for a grid snap, which draws none.
  final double? line;
  final Bounds? target;
  final bool seen;

  bool within(double threshold) => seen && delta.abs() <= threshold;

  /// Keeps [candidate] when it is strictly closer.
  ///
  /// Strictly: the first candidate at a given distance wins, and elements are
  /// offered before the grid, so a tie goes to the element.
  _Best consider(double candidate, double? line, Bounds? target) {
    if (!candidate.isFinite) return this;
    if (seen && candidate.abs() >= delta.abs()) return this;
    return _Best(candidate, line, target, true);
  }
}
