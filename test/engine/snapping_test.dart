import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/snapping.dart';
import 'package:inkpad/state/snap_settings.dart';

Bounds box(double left, double top, double right, double bottom) =>
    Bounds(left: left, top: top, right: right, bottom: bottom);

/// A 100 x 100 box sitting at the origin, and a neighbour to its right.
const _target = Bounds(left: 200, top: 200, right: 300, bottom: 300);

/// `SnapResult` is a record, and a record compares its `List` field by
/// identity — two empty lists are never equal. Assert the fields.
void expectNoSnap(SnapResult result) {
  expect(result.dx, 0);
  expect(result.dy, 0);
  expect(result.guides, isEmpty);
}

SnapResult snap(
  Bounds moving, {
  List<Bounds> targets = const [_target],
  double threshold = 6,
  double? gridSize,
}) => snapBounds(
  moving: moving,
  targets: targets,
  threshold: threshold,
  gridSize: gridSize,
);

void main() {
  group('17.2 element snapping', () {
    test('a near edge pulls the box onto it', () {
      // Left edge at 203, target's left at 200: three pixels away.
      final result = snap(box(203, 500, 303, 600));
      expect(result.dx, -3);
      expect(result.dy, 0);
    });

    test('an edge outside the threshold does not', () {
      expect(snap(box(210, 500, 310, 600)).dx, 0);
    });

    test('right edges align to each other', () {
      // Right edge at 297; target's right at 300.
      final result = snap(box(197, 500, 297, 600));
      expect(result.dx, 3);
    });

    test('centres align to each other', () {
      // Centre at 248; target's centre at 250.
      final result = snap(box(198, 500, 298, 600));
      expect(result.dx, 2);
    });

    test('a left edge can snap to a target\'s right edge', () {
      final result = snap(box(302, 500, 402, 600));
      expect(result.dx, -2, reason: '302 pulled onto 300');
    });

    test('the two axes are decided independently', () {
      final result = snap(
        box(203, 197, 303, 297),
        targets: [_target, box(600, 200, 700, 300)],
      );
      expect(result.dx, -3, reason: 'left onto left');
      expect(result.dy, 3, reason: 'top onto top');
    });

    test('the nearest candidate wins', () {
      // Left edge at 201 (1 away from 200) and right at 301 (1 from 300).
      // Both are 1 away; the first considered wins, deterministically.
      final result = snap(box(201, 500, 301, 600));
      expect(result.dx.abs(), 1);
    });

    test('nothing to snap to means no snap', () {
      expectNoSnap(snap(box(203, 500, 303, 600), targets: const []));
    });

    test('a threshold of zero disables snapping entirely', () {
      expectNoSnap(snap(box(203, 500, 303, 600), threshold: 0));
    });

    test(
      'an exact alignment is a zero-delta snap that still draws a guide',
      () {
        final result = snap(box(200, 500, 300, 600));
        expect(result.dx, 0);
        expect(result.guides.where((g) => g.vertical), isNotEmpty);
      },
    );
  });

  group('17.2 guides', () {
    test('a vertical snap draws a vertical guide at the shared edge', () {
      final result = snap(box(203, 500, 303, 600));
      final guide = result.guides.singleWhere((g) => g.vertical);

      expect(guide.position, 200);
      // Spans from the target's top to the moved box's bottom.
      expect(guide.start, 200);
      expect(guide.end, 600);
    });

    test('a horizontal snap draws a horizontal guide', () {
      final result = snap(box(500, 203, 600, 303));
      final guide = result.guides.singleWhere((g) => !g.vertical);
      expect(guide.position, 200);
      expect(guide.start, 200);
      expect(guide.end, 600);
    });

    test('snapping both axes draws both guides', () {
      final result = snap(box(203, 203, 303, 303));
      expect(result.guides, hasLength(2));
    });

    test('the guide is measured against where the box lands, not where it '
        'was', () {
      final result = snap(box(203, 500, 303, 600));
      final guide = result.guides.singleWhere((g) => g.vertical);
      // The moved box spans 500..600 in y, not 497..597.
      expect(guide.end, 600);
    });

    test('no snap, no guides', () {
      expect(snap(box(500, 500, 600, 600)).guides, isEmpty);
    });
  });

  group('17.2 grid snapping', () {
    test('an edge is pulled onto the nearest grid line', () {
      final result = snap(
        box(23, 500, 123, 600),
        targets: const [],
        gridSize: 20,
      );
      expect(result.dx, -3);
    });

    test('it rounds to the nearest line, in either direction', () {
      expect(snap(box(18, 0, 118, 10), targets: const [], gridSize: 20).dx, 2);
      expect(snap(box(22, 0, 122, 10), targets: const [], gridSize: 20).dx, -2);
    });

    test('a grid snap draws no guide: the grid is already visible', () {
      final result = snap(
        box(23, 500, 123, 600),
        targets: const [],
        gridSize: 20,
      );
      expect(result.dx, isNot(0));
      expect(result.guides, isEmpty);
    });

    test('a grid line beyond the threshold does not pull', () {
      expect(snap(box(30, 0, 130, 10), targets: const [], gridSize: 20).dx, 0);
    });

    test('an element beats the grid at the same distance', () {
      // Left edge at 203: 3 from the element's 200, 3 from the grid line 200.
      final result = snap(box(203, 500, 303, 600), gridSize: 20);
      expect(result.dx, -3);
      expect(result.guides, isNotEmpty, reason: 'it snapped to the element');
    });

    test('a nearer grid line beats a further element', () {
      // Left at 205: 5 from the element's 200, 0 from the grid line 205? No —
      // grid 5 puts a line exactly at 205, so the grid wins with a zero delta.
      final result = snap(box(205, 500, 305, 600), gridSize: 5);
      expect(result.dx, 0);
      expect(result.guides, isEmpty);
    });

    test('a grid size of zero is ignored, not a division by zero', () {
      expectNoSnap(
        snap(box(23, 500, 123, 600), targets: const [], gridSize: 0),
      );
    });
  });

  group('17.2 snapPoint', () {
    test('a bare point snaps to an element edge', () {
      final result = snapPoint(
        x: 203,
        y: 500,
        targets: const [_target],
        threshold: 6,
      );
      expect(result.dx, -3);
    });

    test('a bare point snaps to the grid', () {
      final result = snapPoint(
        x: 23,
        y: 41,
        targets: const [],
        threshold: 6,
        gridSize: 20,
      );
      expect(result.dx, -3);
      expect(result.dy, -1);
    });
  });

  group('17.2 settings', () {
    test('a fresh document snaps to elements but shows no grid', () {
      const settings = SnapSettings();
      expect(settings.snapToElements, isTrue);
      expect(settings.showGrid, isFalse);
      expect(settings.activeGrid, isNull);
      expect(settings.anySnapping, isTrue);
    });

    test('the grid is only a snap target when it is on', () {
      const on = SnapSettings(snapToGrid: true, gridSize: 25);
      expect(on.activeGrid, 25);
    });

    test('turning both off turns snapping off', () {
      const off = SnapSettings(snapToElements: false);
      expect(off.anySnapping, isFalse);
    });
  });
}
