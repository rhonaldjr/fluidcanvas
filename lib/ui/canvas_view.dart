import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Default page size in document space (logical pixels at 100% zoom).
/// Phase 1.4 replaces these with values read from `SkdDocument`.
const double kDefaultCanvasWidth = 1920;
const double kDefaultCanvasHeight = 1080;

/// Gap between the page and the edge of the viewport, in screen pixels.
const double _viewportMargin = 32;

/// The gray backdrop with the white document page centered on it.
///
/// The page is scaled to fit the viewport, never magnified past 100%. Phase 10
/// replaces this fixed fit-to-viewport scale with a real pan/zoom transform.
class CanvasView extends StatelessWidget {
  const CanvasView({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF6E6E6E),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = math.max(
            0.0,
            constraints.maxWidth - _viewportMargin * 2,
          );
          final availableHeight = math.max(
            0.0,
            constraints.maxHeight - _viewportMargin * 2,
          );

          final fit = math.min(
            availableWidth / kDefaultCanvasWidth,
            availableHeight / kDefaultCanvasHeight,
          );
          // Guard against a zero-sized or unbounded viewport.
          final scale = fit.isFinite ? fit.clamp(0.0, 1.0) : 0.0;

          return Center(
            child: SizedBox(
              key: const Key('canvas-page'),
              width: kDefaultCanvasWidth * scale,
              height: kDefaultCanvasHeight * scale,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
