import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/domain/commands/commands.dart'
    show AddElementCommand, kMinCanvasHeight, kMinCanvasWidth;
import 'package:inkpad/engine/debouncer.dart';
import 'package:inkpad/engine/pointer_input.dart';
import 'package:inkpad/engine/renderer/infinite_painter.dart';
import 'package:inkpad/engine/renderer/layer_stack_painter.dart';
import 'package:inkpad/engine/hit_test.dart';
import 'package:inkpad/engine/shape_drag.dart';
import 'package:inkpad/engine/smoothing.dart';
import 'package:inkpad/engine/snapping.dart';
import 'package:inkpad/engine/stabilizer.dart';
import 'package:inkpad/engine/thinning.dart';
import 'package:inkpad/engine/view_transform.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/guides_painter.dart';
import 'package:inkpad/ui/selection_overlay.dart';
import 'package:inkpad/ui/text_box_editor.dart';
import 'package:uuid/uuid.dart';

/// Gap between the page and the edge of the viewport, in screen pixels.
const double kViewportMargin = 32;

/// How long the window must be still before the canvas resize is committed.
const Duration kResizeDebounce = Duration(milliseconds: 250);

/// The canvas size that fits [viewport], leaving [kViewportMargin] on every
/// side and never dropping below the minimum.
///
/// A window collapsed to nothing would otherwise scale the drawing to nothing
/// with it.
({int width, int height}) canvasSizeForViewport(Size viewport) => (
  width: math.max(
    kMinCanvasWidth,
    (viewport.width - kViewportMargin * 2).floor(),
  ),
  height: math.max(
    kMinCanvasHeight,
    (viewport.height - kViewportMargin * 2).floor(),
  ),
);

/// Id given to the stroke while it is still under the pointer. It never reaches
/// the document: [_StrokeCaptureState] mints a fresh id when committing.
const String kLiveStrokeId = 'live';

/// The gray backdrop with the white document page on it.
///
/// The page sits where the session's [ViewTransform] puts it: centred and
/// fitted until the user zooms or pans, after which it is theirs. That
/// transform is a *view*, and never touches the document — unlike task 8.3's
/// canvas resize, which scales every element and can be undone.
class CanvasView extends ConsumerStatefulWidget {
  const CanvasView({super.key});

  /// Page scale that fits a [documentWidth] x [documentHeight] page inside
  /// [viewport], leaving [kViewportMargin] on every side. Never magnifies past
  /// 100%; returns 0 when the viewport cannot fit anything.
  static double fitScale({
    required Size viewport,
    required int documentWidth,
    required int documentHeight,
  }) {
    final availableWidth = math.max(0.0, viewport.width - kViewportMargin * 2);
    final availableHeight = math.max(
      0.0,
      viewport.height - kViewportMargin * 2,
    );

    final fit = math.min(
      availableWidth / documentWidth,
      availableHeight / documentHeight,
    );
    // Guard against a zero-sized or unbounded viewport.
    return fit.isFinite ? fit.clamp(0.0, 1.0) : 0.0;
  }

  @override
  ConsumerState<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends ConsumerState<CanvasView> {
  /// A window drag emits a resize per frame; act once the drag stops.
  final Debouncer _resizeDebouncer = Debouncer(duration: kResizeDebounce);

  /// Whether the document has already adopted a window size.
  ///
  /// Only the very first fit is immediate. Testing "the document is still
  /// empty" instead would make *every* resize of a blank document immediate,
  /// and the debounce would never engage.
  bool _didInitialFit = false;

  @override
  void dispose() {
    _resizeDebouncer.dispose();
    super.dispose();
  }

  /// Makes the document's canvas follow the viewport.
  ///
  /// The very first fit — an untouched document adopting the window it opened
  /// in — happens on the next frame, so the canvas is right immediately. Later
  /// fits are debounced: a window drag emits a resize per frame, and the page
  /// keeps drawing through the fit-to-viewport transform until the drag stops.
  void _scheduleResize(Size viewport) {
    final target = canvasSizeForViewport(viewport);
    final session = ref.read(activeSessionProvider);
    final document = session.document;
    if (document.canvasWidth == target.width &&
        document.canvasHeight == target.height) {
      _resizeDebouncer.cancel();
      return;
    }

    if (!_didInitialFit && document.isEmpty && !session.canUndo) {
      _didInitialFit = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit(target));
    } else {
      _resizeDebouncer(() => _fit(target));
    }
  }

  void _fit(({int width, int height}) target) {
    if (!mounted) return;
    if (!ref.read(activeSessionProvider).fitToWindow) return;
    ref
        .read(sessionsProvider.notifier)
        .fitCanvasToWindow(target.width, target.height);
  }

  @override
  Widget build(BuildContext context) {
    // Shared with the layer panel's thumbnails; owned by the provider.
    final cache = ref.watch(layerCacheProvider);
    final session = ref.watch(activeSessionProvider);
    final document = session.document;
    final points = ref.watch(currentStrokeProvider);
    final brush = ref.watch(brushProvider);
    final tool = ref.watch(toolProvider);

    // A layer removed from the document must not keep holding its image.
    cache.retainOnly([for (final layer in document.layers) layer.id]);

    final liveShape = ref.watch(currentShapeProvider);
    final liveConnector = ref.watch(currentConnectorProvider);

    // The live stroke is a real Stroke so it paints through exactly the code
    // that will paint it once committed — including the eraser's blend mode.
    final liveStroke = points.isEmpty || !tool.drawsStroke
        ? null
        : Stroke(
            id: kLiveStrokeId,
            colorRGBA: brush.colorRGBA,
            baseWidth: brush.baseWidth,
            toolId: tool.strokeToolId!,
            points: points,
          );

    // Split the stack so only the active layer repaints while drawing.
    final activeIndex = document.indexOfLayer(session.activeLayerId);
    final below = document.layers.sublist(0, activeIndex);
    final active = document.layers.sublist(activeIndex, activeIndex + 1);
    final above = document.layers.sublist(activeIndex + 1);

    return ColoredBox(
      color: const Color(0xFF6E6E6E),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isInfinite = document.isInfinite;
          // An infinite document never resizes to follow the window; you pan
          // and zoom over it instead.
          if (!isInfinite &&
              session.fitToWindow &&
              constraints.biggest.isFinite) {
            _scheduleResize(constraints.biggest);
          }

          final viewport = constraints.biggest;
          // A bounded page fits the window; an infinite one has no page to fit,
          // so its "fitted" scale is simply 100%.
          final fitScale = isInfinite
              ? 1.0
              : CanvasView.fitScale(
                  viewport: viewport,
                  documentWidth: document.canvasWidth,
                  documentHeight: document.canvasHeight,
                );
          final scale = session.view.scaleFor(fitScale);

          // Where document (0, 0) sits on screen. A bounded page is placed so
          // its top-left is document (0, 0); an infinite canvas centres the
          // origin in the viewport and shifts it by the pan.
          final Offset docOrigin;
          if (isInfinite) {
            docOrigin = Offset(
              viewport.width / 2 + session.view.panX,
              viewport.height / 2 + session.view.panY,
            );
          } else {
            final o = pageOrigin(
              view: session.view,
              viewportWidth: viewport.width,
              viewportHeight: viewport.height,
              documentWidth: document.canvasWidth,
              documentHeight: document.canvasHeight,
              scale: scale,
            );
            docOrigin = Offset(o.x, o.y);
          }

          // The status bar and the zoom shortcuts read these rather than
          // digging into the tree.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ref.read(pageScaleProvider.notifier).set(scale);
            ref.read(viewportProvider.notifier).set(viewport, fitScale);
          });

          // The overlays that sit over the drawing, shared by both modes. Their
          // origin is where document (0, 0) is *within their box*: zero inside a
          // positioned bounded page, the pan offset over an infinite canvas.
          final overlayOrigin = isInfinite ? docOrigin : Offset.zero;
          Widget canvasStack(Widget layers) => Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              if (ref.watch(snapSettingsProvider).showGrid)
                RepaintBoundary(
                  child: CustomPaint(
                    painter: GridPainter(
                      gridSize: ref.watch(snapSettingsProvider).gridSize,
                      scale: scale,
                      origin: overlayOrigin,
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                ),
              layers,
              RepaintBoundary(
                child: CustomPaint(
                  painter: SelectionOverlayPainter(
                    box: session.selection.isEmpty
                        ? null
                        : session.selectionBounds,
                    marquee: ref.watch(marqueeProvider),
                    scale: scale,
                    origin: overlayOrigin,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              RepaintBoundary(
                child: CustomPaint(
                  painter: GuidesPainter(
                    guides: ref.watch(snapGuidesProvider),
                    scale: scale,
                    origin: overlayOrigin,
                    color: const Color(0xFFE91E63),
                  ),
                ),
              ),
              StrokeCapture(scale: scale, origin: overlayOrigin),
              TextBoxEditor(scale: scale, origin: overlayOrigin),
            ],
          );

          if (isInfinite) {
            return _NavigationLayer(
              viewport: viewport,
              fitScale: fitScale,
              child: SizedBox.expand(
                key: const Key('canvas-page'),
                child: scale > 0
                    ? canvasStack(
                        RepaintBoundary(
                          child: CustomPaint(
                            painter: InfiniteCanvasPainter(
                              layers: document.layers,
                              activeLayerId: session.activeLayerId,
                              scale: scale,
                              origin: docOrigin,
                              liveStroke: liveStroke,
                              liveShape: liveShape,
                              liveConnector: liveConnector,
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            );
          }

          LayerStackPainter painterFor(
            List<Layer> layers,
            String label, {
            Stroke? live,
            Shape? shape,
            Connector? connector,
          }) => LayerStackPainter(
            layers: layers,
            documentWidth: document.canvasWidth,
            documentHeight: document.canvasHeight,
            scale: scale,
            cache: cache,
            liveStroke: live,
            liveShape: shape,
            liveConnector: connector,
            debugLabel: label,
          );

          return _NavigationLayer(
            viewport: viewport,
            fitScale: fitScale,
            child: Stack(
              children: [
                Positioned(
                  left: docOrigin.dx,
                  top: docOrigin.dy,
                  child: SizedBox(
                    key: const Key('canvas-page'),
                    width: document.canvasWidth * scale,
                    height: document.canvasHeight * scale,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      // A zero-size page cannot map screen pixels into document
                      // space, so there is nothing to draw or capture.
                      child: scale > 0
                          ? canvasStack(
                              Stack(
                                fit: StackFit.expand,
                                clipBehavior: Clip.none,
                                children: [
                                  RepaintBoundary(
                                    child: CustomPaint(
                                      painter: painterFor(below, 'below'),
                                    ),
                                  ),
                                  RepaintBoundary(
                                    child: CustomPaint(
                                      painter: painterFor(
                                        active,
                                        'active',
                                        live: liveStroke,
                                        shape: liveShape,
                                        connector: liveConnector,
                                      ),
                                    ),
                                  ),
                                  RepaintBoundary(
                                    child: CustomPaint(
                                      painter: painterFor(above, 'above'),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Collects raw [StrokePoint]s from pointer events over the page and commits
/// them to the active layer on pointer-up.
///
/// From task 6.2 the commit is routed through `AddElementCommand` so it can be
/// undone; today it mutates the session directly.
class StrokeCapture extends ConsumerStatefulWidget {
  const StrokeCapture({
    required this.scale,
    this.origin = Offset.zero,
    super.key,
  });

  /// Page screen size divided by document size.
  final double scale;

  /// Where document (0, 0) sits in the capture box; the pan offset on an
  /// infinite canvas, zero on a bounded page.
  final Offset origin;

  @override
  ConsumerState<StrokeCapture> createState() => _StrokeCaptureState();
}

class _StrokeCaptureState extends ConsumerState<StrokeCapture> {
  /// The pointer currently drawing. A second finger or a second button while a
  /// stroke is in flight is ignored rather than interleaved into it.
  int? _activePointer;

  /// Where a shape drag started. Null unless a shape tool is dragging.
  StrokePoint? _shapeAnchor;

  /// Where a connector drag began. Null unless the connector tool is dragging.
  StrokePoint? _connectorAnchor;

  /// The rough-rendering seed for the shape being dragged out.
  ///
  /// Minted once at pointer-down, not per frame: a shape that reseeded as it
  /// grew would shimmer under the cursor.
  int _shapeSeed = 0;

  /// Where a select-tool drag started, in document space.
  Offset? _selectAnchor;

  /// What the select drag is doing: nothing yet, a marquee, a move, or a
  /// handle drag.
  _SelectGesture _gesture = _SelectGesture.none;

  /// The handle being dragged, and the geometry captured when the drag began.
  ///
  /// Every frame transforms *these* rather than the live document, so the drag
  /// stays one continuous transform and one undo entry.
  Handle? _handle;
  Bounds? _boxAtDragStart;
  List<CanvasElement> _elementsAtDragStart = const [];

  /// The transform the drag has reached so far.
  double _dragFactor = 1;

  /// The box a side-handle drag has reached, in document space.
  Bounds? _dragBox;
  double _dragRotation = 0;
  Offset _dragOffset = Offset.zero;

  /// Smooths the raw input as it streams in, never as a post-pass.
  StrokeSmoother? _smoother;

  /// Decides which raw points survive, before the smoother interpolates
  /// between them. Rebuilt per stroke so a mid-stroke strength change cannot
  /// jerk the anchor.
  Stabilizer? _stabilizer;

  /// The last point fed to the smoother. Thinning measures against the raw
  /// input, not the smoothed output, whose interpolated points are deliberately
  /// closer together than the threshold.
  StrokePoint? _lastRawPoint;

  CurrentStrokeNotifier get _stroke => ref.read(currentStrokeProvider.notifier);

  StrokePoint _pointFrom(PointerEvent event) => documentPoint(
    local: event.localPosition - widget.origin,
    scale: widget.scale,
    pressure: normalizePressure(
      pressure: event.pressure,
      min: event.pressureMin,
      max: event.pressureMax,
    ),
  );

  Tool get _tool => ref.read(toolProvider);

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    // The navigation layer owns middle-drags and every drag while space is
    // held. Drawing with them would leave a stroke along the pan.
    if (event.buttons != kPrimaryButton || spacePanHeld()) return;
    _activePointer = event.pointer;
    final point = _pointFrom(event);

    if (_tool.drawsText) {
      _createTextBox(point);
      return;
    }
    if (_tool.drawsConnector) {
      _connectorAnchor = point;
      return;
    }
    if (_tool == Tool.select) {
      _beginSelect(point);
      return;
    }
    if (_tool.drawsShape) {
      _shapeAnchor = point;
      _shapeSeed = math.Random().nextInt(0xFFFFFFFF);
      return;
    }
    if (!_tool.drawsStroke) return;

    _smoother = StrokeSmoother();
    _stabilizer = Stabilizer(strength: ref.read(stabilizerStrengthProvider));
    _lastRawPoint = point;
    _stroke.begin(_smoother!.add(_stabilizer!.process(point)!).single);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _activePointer) return;
    if (_gesture != _SelectGesture.none) {
      _updateSelect(_pointFrom(event));
      return;
    }
    if (_shapeAnchor != null) {
      _updateLiveShape(_pointFrom(event));
      return;
    }
    if (_connectorAnchor != null) {
      _updateLiveConnector(_pointFrom(event));
      return;
    }
    if (!_tool.drawsStroke) return;
    _feed(_pointFrom(event));
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _activePointer) return;

    if (_tool == Tool.select) {
      _endSelect(_pointFrom(event));
      _endStroke();
      return;
    }
    if (_shapeAnchor != null) {
      _updateLiveShape(_pointFrom(event));
      _showGuides(const []);
      _commitShape();
      _endStroke();
      return;
    }
    if (_connectorAnchor != null) {
      _commitConnector(_pointFrom(event));
      _endStroke();
      return;
    }
    if (!_tool.drawsStroke) {
      _endStroke();
      return;
    }

    _feed(_pointFrom(event));

    // Let the anchor catch up to the cursor before closing the stroke.
    final tail = _stabilizer!.finish();
    if (tail != null) {
      for (final smoothed in _smoother!.add(tail)) {
        _stroke.extend(smoothed);
      }
    }
    for (final point in _smoother!.finish()) {
      _stroke.extend(point);
    }
    _commitStroke();
    _endStroke();
  }

  /// Rebuilds the shape preview from the anchor to [current].
  ///
  /// Shift constrains to a square, circle or 45-degree line; Alt draws out from
  /// the anchor as the centre.
  /// Snaps the corner a shape drag is pulling, so a new box lands on its
  /// neighbours' edges just as a moved one does.
  StrokePoint _snappedCorner(StrokePoint current) {
    final snap = _snapFor(
      Bounds(
        left: current.x,
        top: current.y,
        right: current.x,
        bottom: current.y,
      ),
      const {},
    );
    _showGuides(snap.guides);
    if (snap.dx == 0 && snap.dy == 0) return current;
    return StrokePoint(
      x: current.x + snap.dx,
      y: current.y + snap.dy,
      pressure: current.pressure,
    );
  }

  void _updateLiveShape(StrokePoint rawCurrent) {
    final style = ref.read(shapeStyleProvider);
    final keys = HardwareKeyboard.instance;
    // Alt already means "from the centre" here, and _snapFor reads it as
    // "no snapping" — the two agree: an Alt drag is a deliberate, free one.
    final current = _snappedCorner(rawCurrent);

    ref
        .read(currentShapeProvider.notifier)
        .set(
          shapeFromDrag(
            id: kLiveStrokeId,
            type: _tool.shapeType!,
            anchor: _shapeAnchor!,
            current: current,
            strokeColorRGBA: style.strokeColorRGBA,
            fillColorRGBA: style.fillColorRGBA,
            strokeWidth: style.strokeWidth,
            strokeStyle: style.strokeStyle,
            renderStyle: style.renderStyle,
            seed: _shapeSeed,
            square: keys.isShiftPressed,
            fromCenter: keys.isAltPressed,
          ),
        );
  }

  // -------------------------------------------------------------------
  // Select tool
  // -------------------------------------------------------------------

  SessionsNotifier get _sessions => ref.read(sessionsProvider.notifier);

  void _beginSelect(StrokePoint point) {
    final session = ref.read(activeSessionProvider);
    final at = Offset(point.x, point.y);
    _selectAnchor = at;
    _dragFactor = 1;
    _dragBox = null;
    _dragRotation = 0;
    _dragOffset = Offset.zero;

    // A handle wins over whatever sits under it.
    final box = session.selectionBounds;
    if (box != null) {
      final handle = handleAt(box, at.dx, at.dy, widget.scale);
      if (handle != null) {
        _handle = handle;
        _boxAtDragStart = box;
        _elementsAtDragStart = session.selectedElements;
        _gesture = switch (handle) {
          Handle.rotate => _SelectGesture.rotate,
          // A side handle changes the box on one axis — text rewraps at the
          // same font size — but only for a lone, unrotated, boxed element.
          _ when handle.isEdge && _canBoxResize => _SelectGesture.resizeBox,
          _ => _SelectGesture.resize,
        };
        return;
      }
    }

    final hit = topmostElementAt(session.document.layers, at.dx, at.dy);
    if (hit == null) {
      if (!HardwareKeyboard.instance.isShiftPressed) _sessions.clearSelection();
      _gesture = _SelectGesture.marquee;
      ref.read(marqueeProvider.notifier).set(Bounds.point(at.dx, at.dy));
      return;
    }

    if (HardwareKeyboard.instance.isShiftPressed) {
      _sessions.toggleSelected(hit.id);
    } else if (!session.selection.contains(hit.id)) {
      _sessions.setSelection({hit.id});
    }
    _elementsAtDragStart = ref.read(activeSessionProvider).selectedElements;
    _gesture = _SelectGesture.move;
  }

  /// Whether the element captured at drag start takes a one-axis box resize.
  bool get _canBoxResize =>
      _elementsAtDragStart.length == 1 &&
      canResizeBox(_elementsAtDragStart.single);

  void _updateSelect(StrokePoint point) {
    final at = Offset(point.x, point.y);
    final from = _selectAnchor!;

    switch (_gesture) {
      case _SelectGesture.none:
        return;

      case _SelectGesture.marquee:
        ref.read(marqueeProvider.notifier).set(_boundsBetween(from, at));

      case _SelectGesture.move:
        _dragOffset = at - from;
        final box = _boundsOf(_elementsAtDragStart);
        if (box != null) {
          final snap = _snapFor(
            box.translated(_dragOffset.dx, _dragOffset.dy),
            {for (final e in _elementsAtDragStart) e.id},
          );
          _dragOffset += Offset(snap.dx, snap.dy);
          _showGuides(snap.guides);
        }
        _preview((e) => e.translated(_dragOffset.dx, _dragOffset.dy));

      case _SelectGesture.resize:
        final anchor = anchorFor(_handle!, _boxAtDragStart!);
        _dragFactor = resizeFactor(anchor: anchor, start: from, current: at);
        _preview(
          (e) => e.scaled(_dragFactor, originX: anchor.dx, originY: anchor.dy),
        );

      case _SelectGesture.resizeBox:
        _dragBox = resizeBox(_boxAtDragStart!, _handle!, at);
        _preview((e) => elementWithBox(e, _dragBox!));

      case _SelectGesture.rotate:
        final centre = _dragCentre;
        var wanted = (at - centre).direction - (from - centre).direction;
        if (HardwareKeyboard.instance.isShiftPressed) {
          const step = math.pi / 12; // 15 degrees
          wanted = (wanted / step).roundToDouble() * step;
        }
        _dragRotation = wanted;
        _preview(
          (e) =>
              e.rotated(_dragRotation, originX: centre.dx, originY: centre.dy),
        );
    }
  }

  /// The union of [elements]' boxes, or `null` when none of them has one.
  static Bounds? _boundsOf(List<CanvasElement> elements) {
    Bounds? result;
    for (final element in elements) {
      final box = element.bounds;
      if (box == null) continue;
      result = result == null ? box : result.union(box);
    }
    return result;
  }

  Offset get _dragCentre =>
      Offset(_boxAtDragStart!.centerX, _boxAtDragStart!.centerY);

  /// The boxes a drag may snap to: everything visible except what is moving.
  List<Bounds> _snapTargets(Set<String> moving) {
    final layers = ref.read(activeDocumentProvider).layers;
    return [
      for (final layer in layers)
        if (layer.visible)
          for (final element in layer.elements)
            if (!moving.contains(element.id)) ?element.bounds,
    ];
  }

  /// The snap [snapBounds] would apply to [box], and the guides to draw.
  ///
  /// Alt suspends snapping: the same key that already means "from the centre"
  /// for a shape drag means "leave me alone" for a snap, and no drag uses both.
  SnapResult _snapFor(Bounds box, Set<String> moving) {
    final settings = ref.read(snapSettingsProvider);
    if (!settings.anySnapping || HardwareKeyboard.instance.isAltPressed) {
      return kNoSnap;
    }
    return snapBounds(
      moving: box,
      targets: settings.snapToElements ? _snapTargets(moving) : const [],
      // The threshold is in screen pixels, so it feels the same at every zoom.
      threshold: kSnapThreshold / widget.scale,
      gridSize: settings.activeGrid,
    );
  }

  void _showGuides(List<SnapGuide> guides) =>
      ref.read(snapGuidesProvider.notifier).set(guides);

  /// Redraws the drag from the geometry captured when it started.
  ///
  /// Never from the current document: compounding a transform frame by frame
  /// accumulates float error, and undoing one frame of it is meaningless.
  void _preview(CanvasElement Function(CanvasElement) transform) {
    if (_elementsAtDragStart.isEmpty) return;
    _sessions.previewElements([
      for (final element in _elementsAtDragStart) transform(element),
    ]);
  }

  void _endSelect(StrokePoint point) {
    _showGuides(const []);

    // One command for the whole gesture, built from the captured geometry.
    switch (_gesture) {
      case _SelectGesture.move:
        _sessions.commitMove(
          _elementsAtDragStart,
          _dragOffset.dx,
          _dragOffset.dy,
        );
      case _SelectGesture.resize:
        final anchor = anchorFor(_handle!, _boxAtDragStart!);
        _sessions.commitResize(
          _elementsAtDragStart,
          _dragFactor,
          anchor.dx,
          anchor.dy,
        );
      case _SelectGesture.resizeBox:
        if (_dragBox != null) {
          _sessions.commitResizeBox(_elementsAtDragStart.single, _dragBox!);
        }

      case _SelectGesture.rotate:
        final centre = _dragCentre;
        _sessions.commitRotate(
          _elementsAtDragStart,
          _dragRotation,
          centre.dx,
          centre.dy,
        );
      case _SelectGesture.marquee:
      case _SelectGesture.none:
        break;
    }

    if (_gesture == _SelectGesture.marquee) {
      final marquee = _boundsBetween(_selectAnchor!, Offset(point.x, point.y));
      final layers = ref.read(activeDocumentProvider).layers;
      final inside = elementsWithin(layers, marquee);
      if (inside.isNotEmpty) {
        _sessions.setSelection({
          ...ref.read(activeSessionProvider).selection,
          for (final e in inside) e.id,
        });
      }
    }
    ref.read(marqueeProvider.notifier).clear();
    _gesture = _SelectGesture.none;
    _handle = null;
    _boxAtDragStart = null;
    _elementsAtDragStart = const [];
    _selectAnchor = null;
  }

  static Bounds _boundsBetween(Offset a, Offset b) => Bounds(
    left: math.min(a.dx, b.dx),
    top: math.min(a.dy, b.dy),
    right: math.max(a.dx, b.dx),
    bottom: math.max(a.dy, b.dy),
  );

  /// Default size of a text box placed with a click, in document pixels.
  static const Size _defaultTextBox = Size(260, 60);

  // -------------------------------------------------------------------
  // Connector tool
  // -------------------------------------------------------------------

  /// The element under ([x], [y]) that a connector end may bind to.
  ///
  /// Connectors bind to *siblings*: the top-level elements of the active layer.
  /// A connector cannot bind to another connector, nor to something on another
  /// layer, because a bound end is stored as an index into its own container.
  CanvasElement? _bindTarget(double x, double y) {
    final layer = ref.read(activeSessionProvider).activeLayer;
    for (final element in layer.elements.reversed) {
      if (element is Connector) continue;
      if (element.bounds == null) continue;
      if (hitTestElement(element, x, y, siblings: layer.elements)) {
        return element;
      }
    }
    return null;
  }

  /// The end a press or release at [at] produces: bound when it lands on an
  /// element, free otherwise.
  ConnectorEnd _connectorEndAt(StrokePoint at) {
    final target = _bindTarget(at.x, at.y);
    return target == null
        ? ConnectorEnd.free(at.x, at.y)
        : ConnectorEnd.bound(target.id);
  }

  Connector _connectorFromDrag(
    StrokePoint anchor,
    StrokePoint current,
    String id,
  ) {
    final style = ref.read(shapeStyleProvider);
    return Connector(
      id: id,
      start: _connectorEndAt(anchor),
      end: _connectorEndAt(current),
      strokeColorRGBA: style.strokeColorRGBA,
      strokeWidth: style.strokeWidth,
      strokeStyle: style.strokeStyle,
    );
  }

  void _updateLiveConnector(StrokePoint current) => ref
      .read(currentConnectorProvider.notifier)
      .set(_connectorFromDrag(_connectorAnchor!, current, kLiveStrokeId));

  void _commitConnector(StrokePoint at) {
    final anchor = _connectorAnchor!;
    _connectorAnchor = null;
    ref.read(currentConnectorProvider.notifier).clear();

    // A tap, not a drag: nothing to connect.
    final dx = at.x - anchor.x;
    final dy = at.y - anchor.y;
    if (dx * dx + dy * dy < 4) return;

    final connector = _connectorFromDrag(anchor, at, const Uuid().v4());
    // Both ends on the same element would draw a line from a shape to itself.
    if (connector.start.isBound &&
        connector.start.elementId == connector.end.elementId) {
      return;
    }

    final session = ref.read(activeSessionProvider);
    ref
        .read(sessionsProvider.notifier)
        .run(
          AddElementCommand(layerId: session.activeLayerId, element: connector),
        );
  }

  void _createTextBox(StrokePoint at) {
    final style = ref.read(textStyleProvider);
    final element = TextElement.plain(
      id: const Uuid().v4(),
      x: at.x,
      y: at.y,
      w: _defaultTextBox.width,
      h: _defaultTextBox.height,
      fontFamily: style.fontFamily,
      fontSize: style.fontSize,
      colorRGBA: style.colorRGBA,
    );

    ref.read(sessionsProvider.notifier).addElementToActiveLayer(element);
    ref.read(textEditingProvider.notifier).begin(element);
    // Typing a box then leaving it empty removes it again, so a mis-click
    // leaves nothing behind.
    _activePointer = null;
  }

  void _commitShape() {
    final shape = ref.read(currentShapeProvider);
    if (shape == null) return;

    final box = shape.normalized();
    // A click with a shape tool, or a drag of a few pixels, is a mis-click.
    if (box.w < 1 && box.h < 1) return;

    ref
        .read(sessionsProvider.notifier)
        .addElementToActiveLayer(box.copyWith(id: const Uuid().v4()));
  }

  /// Thins [point] against the last raw input, stabilizes what survives, then
  /// feeds that to the smoother and appends whatever it emits.
  void _feed(StrokePoint point) {
    if (!isFarEnough(_lastRawPoint!, point)) return;
    _lastRawPoint = point;

    final stabilized = _stabilizer!.process(point);
    if (stabilized == null) return;

    for (final smoothed in _smoother!.add(stabilized)) {
      _stroke.extend(smoothed);
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _connectorAnchor = null;
    ref.read(currentConnectorProvider.notifier).clear();
    if (event.pointer != _activePointer) return;
    // A cancelled drag is abandoned, never committed.
    _endStroke();
  }

  void _commitStroke() {
    final points = ref.read(currentStrokeProvider);
    if (points.isEmpty) return;

    final brush = ref.read(brushProvider);
    ref
        .read(sessionsProvider.notifier)
        .addElementToActiveLayer(
          Stroke(
            id: const Uuid().v4(),
            colorRGBA: brush.colorRGBA,
            baseWidth: brush.baseWidth,
            toolId: ref.read(toolProvider).strokeToolId!,
            points: points,
          ),
        );
  }

  void _endStroke() {
    _stroke.clear();
    ref.read(currentShapeProvider.notifier).clear();
    _gesture = _SelectGesture.none;
    _handle = null;
    _selectAnchor = null;
    _activePointer = null;
    _shapeAnchor = null;
    _smoother = null;
    _stabilizer = null;
    _lastRawPoint = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: const SizedBox.expand(),
    );
  }
}

/// What a select-tool drag is doing.
enum _SelectGesture { none, marquee, move, resize, resizeBox, rotate }

/// Pans and zooms the page: Ctrl+scroll, trackpad gestures, middle-drag and
/// space-drag.
///
/// It sits *around* the page rather than on it, so a drag that leaves the page
/// keeps panning, and so a gesture over the gray backdrop still works. The
/// page's own [StrokeCapture] ignores anything this layer claims — a middle
/// button, or any button while space is held — rather than drawing with it.
class _NavigationLayer extends ConsumerStatefulWidget {
  const _NavigationLayer({
    required this.viewport,
    required this.fitScale,
    required this.child,
  });

  final Size viewport;
  final double fitScale;
  final Widget child;

  @override
  ConsumerState<_NavigationLayer> createState() => _NavigationLayerState();
}

class _NavigationLayerState extends ConsumerState<_NavigationLayer> {
  /// The pointer dragging the page, and where it was last frame.
  int? _panPointer;
  Offset? _panFrom;

  /// The scale reported by the last trackpad pan/zoom update, so a pinch can
  /// be applied as a ratio rather than an absolute.
  double _gestureScale = 1;

  /// Whether the middle mouse button is currently down. A wheel turned while it
  /// is held zooms about the cursor, a shortcut for the mouse that has no easy
  /// Ctrl reach. The button still pans by *drag* (14.2); the two never collide
  /// because a pan is a move and a zoom is a wheel signal.
  bool _middleButtonHeld = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Space turns the whole canvas into a hand. Rebuild so the cursor changes
  /// the moment it is pressed, not on the next pointer event.
  bool _onKey(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.space) return false;
    if (event is KeyRepeatEvent) return false;
    setState(() {});
    // Never claim the key: a text box being edited needs its spaces.
    return false;
  }

  bool get _spaceHeld => spacePanHeld();

  SessionsNotifier get _sessions => ref.read(sessionsProvider.notifier);

  ViewTransform get _view => ref.read(activeSessionProvider).view;

  SkdDocument get _document => ref.read(activeDocumentProvider);

  void _zoomBy(double factor, Offset focus) => _sessions.setView(
    zoomByFactor(
      _view,
      factor: factor,
      focusX: focus.dx,
      focusY: focus.dy,
      viewportWidth: widget.viewport.width,
      viewportHeight: widget.viewport.height,
      documentWidth: _document.canvasWidth,
      documentHeight: _document.canvasHeight,
      fitScale: widget.fitScale,
    ),
  );

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    // Ctrl/Cmd+wheel, or a wheel turned with the middle button held, zooms
    // about the cursor. `event.buttons` covers platforms that report the held
    // button on the signal; `_middleButtonHeld` covers those that do not.
    final zoom =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        _middleButtonHeld ||
        event.buttons == kMiddleMouseButton;
    if (zoom) {
      _zoomBy(zoomFactorForScroll(event.scrollDelta.dy), event.localPosition);
      return;
    }
    // A plain wheel scrolls the page past the window, as every viewer does.
    _sessions.panBy(-event.scrollDelta.dx, -event.scrollDelta.dy);
  }

  /// True when this pointer is here to pan rather than to draw.
  bool _isPanPointer(PointerDownEvent event) =>
      event.buttons == kMiddleMouseButton || _spaceHeld;

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons == kMiddleMouseButton) _middleButtonHeld = true;
    if (_panPointer != null || !_isPanPointer(event)) return;
    _panPointer = event.pointer;
    _panFrom = event.localPosition;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _panPointer) return;
    final from = _panFrom!;
    _panFrom = event.localPosition;
    _sessions.panBy(
      event.localPosition.dx - from.dx,
      event.localPosition.dy - from.dy,
    );
  }

  void _endPan(PointerEvent event) {
    // Any pointer lifting ends the middle-button hold; the common flow is
    // press-middle, wheel, release-middle.
    _middleButtonHeld = false;
    if (event.pointer != _panPointer) return;
    _panPointer = null;
    _panFrom = null;
  }

  // Trackpads: two fingers pan, a pinch zooms. Both arrive as one gesture.
  void _onPanZoomStart(PointerPanZoomStartEvent event) => _gestureScale = 1;

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (event.scale != _gestureScale && event.scale > 0) {
      _zoomBy(event.scale / _gestureScale, event.localPosition);
      _gestureScale = event.scale;
      return;
    }
    _sessions.panBy(event.panDelta.dx, event.panDelta.dy);
  }

  @override
  Widget build(BuildContext context) {
    final panning = _panPointer != null;
    return MouseRegion(
      cursor: panning
          ? SystemMouseCursors.grabbing
          : _spaceHeld
          ? SystemMouseCursors.grab
          : MouseCursor.defer,
      child: Listener(
        key: const Key('canvas-navigation'),
        onPointerSignal: _onSignal,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _endPan,
        onPointerCancel: _endPan,
        onPointerPanZoomStart: _onPanZoomStart,
        onPointerPanZoomUpdate: _onPanZoomUpdate,
        child: widget.child,
      ),
    );
  }
}

/// Whether space is held, which turns any drag into a pan.
///
/// Read by [StrokeCapture] too, so a space-drag never leaves a stroke behind.
bool spacePanHeld() => HardwareKeyboard.instance.logicalKeysPressed.contains(
  LogicalKeyboardKey.space,
);

/// Zooms the active document by [factor], about [focus] in viewport space or
/// about the viewport's centre when there is no cursor to pivot on.
///
/// Lives here rather than on the notifier because zooming needs the viewport,
/// and only the canvas knows how big it is.
void zoomActiveBy(WidgetRef ref, double factor, {Offset? focus}) {
  final viewport = ref.read(viewportProvider);
  if (viewport.size.isEmpty) return;

  final session = ref.read(activeSessionProvider);
  final document = session.document;
  final pivot = focus ?? viewport.size.center(Offset.zero);

  ref
      .read(sessionsProvider.notifier)
      .setView(
        zoomByFactor(
          session.view,
          factor: factor,
          focusX: pivot.dx,
          focusY: pivot.dy,
          viewportWidth: viewport.size.width,
          viewportHeight: viewport.size.height,
          documentWidth: document.canvasWidth,
          documentHeight: document.canvasHeight,
          fitScale: viewport.fitScale,
        ),
      );
}
