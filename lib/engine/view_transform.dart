import 'dart:math' as math;

/// Zoom limits. Below 10% a stroke is a smudge; above 800% a pixel is a tile.
const double kMinZoom = 0.1;
const double kMaxZoom = 8.0;

/// How much one mouse-wheel notch zooms.
const double kZoomStep = 1.1;

/// How the page is drawn inside the viewport: a **view** transform.
///
/// Never touches the document. Task 8.3's canvas resize is the opposite: it
/// scales every element and is undoable. Zooming to 800% and back leaves the
/// document byte-for-byte identical, so nothing here is a command.
///
/// One per [DocumentSession], so each tab keeps its own zoom and scroll.
class ViewTransform {
  const ViewTransform({
    this.zoom = 1,
    this.panX = 0,
    this.panY = 0,
    this.fitted = true,
  }) : assert(zoom > 0, 'zoom must be positive');

  /// The view a document opens with: the whole page, centred.
  static const ViewTransform initial = ViewTransform();

  /// The scale the page is drawn at, when [fitted] is false.
  final double zoom;

  /// How far the page is dragged from the centre of the viewport, in screen
  /// pixels.
  final double panX;
  final double panY;

  /// Whether [zoom] is ignored in favour of "as large as fits".
  ///
  /// A fresh document fits its viewport, and Ctrl+0 puts it back. The moment
  /// the user zooms, the scale becomes theirs and stops tracking the window.
  final bool fitted;

  bool get isPanned => panX != 0 || panY != 0;

  /// The scale the page actually draws at, given the [fitScale] that would
  /// make it fill the viewport.
  double scaleFor(double fitScale) => fitted ? fitScale : zoom;

  ViewTransform copyWith({
    double? zoom,
    double? panX,
    double? panY,
    bool? fitted,
  }) => ViewTransform(
    zoom: zoom ?? this.zoom,
    panX: panX ?? this.panX,
    panY: panY ?? this.panY,
    fitted: fitted ?? this.fitted,
  );

  /// Moved by a drag of ([dx], [dy]) screen pixels.
  ///
  /// Panning does not clear [fitted]: dragging a page aside says nothing about
  /// how big it should be, and the window may still resize it.
  ViewTransform pannedBy(double dx, double dy) =>
      copyWith(panX: panX + dx, panY: panY + dy);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ViewTransform &&
          zoom == other.zoom &&
          panX == other.panX &&
          panY == other.panY &&
          fitted == other.fitted;

  @override
  int get hashCode => Object.hash(zoom, panX, panY, fitted);

  @override
  String toString() =>
      'ViewTransform(${fitted ? 'fit' : zoom.toStringAsFixed(2)}, '
      '$panX, $panY)';
}

/// Where the page's top-left corner sits in the viewport, in screen pixels.
///
/// The page is centred, then dragged by the pan. Everything that converts
/// between screen and document space goes through this, so there is one
/// definition of where the page is.
({double x, double y}) pageOrigin({
  required ViewTransform view,
  required double viewportWidth,
  required double viewportHeight,
  required int documentWidth,
  required int documentHeight,
  required double scale,
}) => (
  x: (viewportWidth - documentWidth * scale) / 2 + view.panX,
  y: (viewportHeight - documentHeight * scale) / 2 + view.panY,
);

/// The view that zooms to [targetZoom] while holding the document point under
/// ([focusX], [focusY]) — a viewport-space cursor position — still.
///
/// This is what makes Ctrl+scroll feel right: the pixel under the cursor is
/// the pivot, not the centre of the page. Solved rather than iterated, so
/// zooming in and back out returns to the same place.
ViewTransform zoomAround(
  ViewTransform view, {
  required double targetZoom,
  required double focusX,
  required double focusY,
  required double viewportWidth,
  required double viewportHeight,
  required int documentWidth,
  required int documentHeight,
  required double fitScale,
}) {
  final next = targetZoom.clamp(kMinZoom, kMaxZoom);
  final current = view.scaleFor(fitScale);
  if (current <= 0) return view.copyWith(zoom: next, fitted: false);

  final origin = pageOrigin(
    view: view,
    viewportWidth: viewportWidth,
    viewportHeight: viewportHeight,
    documentWidth: documentWidth,
    documentHeight: documentHeight,
    scale: current,
  );

  // The document point the cursor is over, before the zoom.
  final docX = (focusX - origin.x) / current;
  final docY = (focusY - origin.y) / current;

  // Solve pan from `focus = centre - size*z/2 + pan + doc*z`.
  return ViewTransform(
    zoom: next,
    panX: focusX - viewportWidth / 2 - (docX - documentWidth / 2) * next,
    panY: focusY - viewportHeight / 2 - (docY - documentHeight / 2) * next,
    fitted: false,
  );
}

/// [view] zoomed by [factor] about a cursor, clamped to the zoom limits.
ViewTransform zoomByFactor(
  ViewTransform view, {
  required double factor,
  required double focusX,
  required double focusY,
  required double viewportWidth,
  required double viewportHeight,
  required int documentWidth,
  required int documentHeight,
  required double fitScale,
}) => zoomAround(
  view,
  targetZoom: view.scaleFor(fitScale) * factor,
  focusX: focusX,
  focusY: focusY,
  viewportWidth: viewportWidth,
  viewportHeight: viewportHeight,
  documentWidth: documentWidth,
  documentHeight: documentHeight,
  fitScale: fitScale,
);

/// The zoom a scroll of [scrollDelta] logical pixels implies.
///
/// Wheels report ±kZoomStep-sized notches; trackpads report a continuous
/// stream, so the step is exponential in the delta rather than per event.
double zoomFactorForScroll(double scrollDelta) =>
    math.pow(kZoomStep, -scrollDelta / 50).toDouble();
