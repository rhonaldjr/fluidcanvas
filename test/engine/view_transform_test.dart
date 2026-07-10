import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/engine/view_transform.dart';

const _viewport = (width: 1000.0, height: 800.0);
const _doc = (width: 500, height: 400);

/// Where the document point ([x], [y]) lands on screen under [view].
({double x, double y}) project(
  ViewTransform view,
  double x,
  double y, {
  double fitScale = 1,
}) {
  final scale = view.scaleFor(fitScale);
  final origin = pageOrigin(
    view: view,
    viewportWidth: _viewport.width,
    viewportHeight: _viewport.height,
    documentWidth: _doc.width,
    documentHeight: _doc.height,
    scale: scale,
  );
  return (x: origin.x + x * scale, y: origin.y + y * scale);
}

ViewTransform zoomTo(ViewTransform view, double zoom, double fx, double fy) =>
    zoomAround(
      view,
      targetZoom: zoom,
      focusX: fx,
      focusY: fy,
      viewportWidth: _viewport.width,
      viewportHeight: _viewport.height,
      documentWidth: _doc.width,
      documentHeight: _doc.height,
      fitScale: 1,
    );

void main() {
  group('14.1 the page sits where the transform says', () {
    test('an untouched view centres the page', () {
      final origin = pageOrigin(
        view: ViewTransform.initial,
        viewportWidth: _viewport.width,
        viewportHeight: _viewport.height,
        documentWidth: _doc.width,
        documentHeight: _doc.height,
        scale: 1,
      );
      expect(origin.x, 250);
      expect(origin.y, 200);
    });

    test('a fitted view ignores its zoom', () {
      const view = ViewTransform(zoom: 4);
      expect(view.scaleFor(0.5), 0.5);
      expect(view.copyWith(fitted: false).scaleFor(0.5), 4);
    });

    test('panning moves the page, not the document', () {
      final panned = ViewTransform.initial.pannedBy(30, -10);
      expect(project(panned, 0, 0), (x: 280.0, y: 190.0));
      expect(panned.isPanned, isTrue);
    });

    test('panning does not stop the page fitting the window', () {
      // Dragging a page aside says nothing about how big it should be.
      expect(ViewTransform.initial.pannedBy(50, 0).fitted, isTrue);
    });
  });

  group('14.1 zoom holds the point under the cursor', () {
    test('the pixel under the cursor does not move', () {
      const cursor = (x: 700.0, y: 300.0);
      final zoomed = zoomTo(ViewTransform.initial, 3, cursor.x, cursor.y);

      // The document point that was under the cursor before...
      final before = project(ViewTransform.initial, 450, 100);
      expect(before, (x: cursor.x, y: cursor.y));

      // ...is still under it after.
      final after = project(zoomed, 450, 100);
      expect(after.x, closeTo(cursor.x, 1e-9));
      expect(after.y, closeTo(cursor.y, 1e-9));
    });

    test('zooming in and back out returns to where it started', () {
      var view = zoomTo(ViewTransform.initial, 4, 700, 300);
      view = zoomTo(view, 1, 700, 300);

      expect(view.zoom, 1);
      expect(view.panX, closeTo(0, 1e-9));
      expect(view.panY, closeTo(0, 1e-9));
    });

    test('zooming about the centre leaves the page centred', () {
      final view = zoomTo(ViewTransform.initial, 2, 500, 400);
      expect(view.panX, closeTo(0, 1e-9));
      expect(view.panY, closeTo(0, 1e-9));
    });

    test('any zoom clears fitted: the scale is now the user\'s', () {
      expect(zoomTo(ViewTransform.initial, 2, 0, 0).fitted, isFalse);
    });

    test('zoom is clamped to the limits, not refused', () {
      expect(zoomTo(ViewTransform.initial, 99, 500, 400).zoom, kMaxZoom);
      expect(zoomTo(ViewTransform.initial, 0.001, 500, 400).zoom, kMinZoom);
    });

    test('a clamped zoom still holds the cursor point', () {
      const cursor = (x: 700.0, y: 300.0);
      final clamped = zoomTo(ViewTransform.initial, 99, cursor.x, cursor.y);
      final after = project(clamped, 450, 100);
      expect(after.x, closeTo(cursor.x, 1e-9));
      expect(after.y, closeTo(cursor.y, 1e-9));
    });

    test('zooming out of a fitted view starts from the fit scale', () {
      // A page fitted at 50% zoomed by 2 is at 100%, not 200%.
      final view = zoomByFactor(
        ViewTransform.initial,
        factor: 2,
        focusX: 500,
        focusY: 400,
        viewportWidth: _viewport.width,
        viewportHeight: _viewport.height,
        documentWidth: _doc.width,
        documentHeight: _doc.height,
        fitScale: 0.5,
      );
      expect(view.zoom, closeTo(1, 1e-9));
    });

    test('a zero-scale viewport does not divide by zero', () {
      final view = zoomAround(
        ViewTransform.initial,
        targetZoom: 2,
        focusX: 0,
        focusY: 0,
        viewportWidth: 0,
        viewportHeight: 0,
        documentWidth: _doc.width,
        documentHeight: _doc.height,
        fitScale: 0,
      );
      expect(view.zoom, 2);
      expect(view.panX, 0);
    });
  });

  group('14.1 scroll to zoom', () {
    test('scrolling up zooms in, down zooms out', () {
      expect(zoomFactorForScroll(-50), closeTo(kZoomStep, 1e-9));
      expect(zoomFactorForScroll(50), closeTo(1 / kZoomStep, 1e-9));
    });

    test('no scroll is no zoom', () {
      expect(zoomFactorForScroll(0), 1);
    });

    test('a trackpad\'s small deltas zoom proportionally, not per event', () {
      // Ten small scrolls equal one large one.
      var factor = 1.0;
      for (var i = 0; i < 10; i++) {
        factor *= zoomFactorForScroll(5);
      }
      expect(factor, closeTo(zoomFactorForScroll(50), 1e-9));
    });
  });

  group('14.1 value semantics', () {
    test('two identical views are equal', () {
      expect(
        const ViewTransform(zoom: 2, panX: 3, fitted: false),
        const ViewTransform(zoom: 2, panX: 3, fitted: false),
      );
    });

    test('fitted is part of the identity', () {
      expect(
        const ViewTransform(zoom: 2),
        isNot(const ViewTransform(zoom: 2, fitted: false)),
      );
    });

    test('a zoom of zero is a bug, not a blank page', () {
      expect(() => ViewTransform(zoom: 0), throwsA(isA<AssertionError>()));
    });
  });
}
