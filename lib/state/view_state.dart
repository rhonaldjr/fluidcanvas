import 'dart:ui' show Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The scale the page is currently drawn at: page screen size divided by
/// document size, after the session's zoom.
///
/// Published by the canvas so the status bar can read it without reaching into
/// the widget tree.
class PageScaleNotifier extends Notifier<double> {
  @override
  double build() => 1;

  void set(double value) {
    if (state != value) state = value;
  }
}

final pageScaleProvider = NotifierProvider<PageScaleNotifier, double>(
  PageScaleNotifier.new,
);

/// The size of the area the page is drawn in, and the scale at which the whole
/// page would fit it.
///
/// Zooming about the viewport centre — Ctrl+= from the keyboard, where there
/// is no cursor to pivot on — needs both, and the shortcut fires far from the
/// `LayoutBuilder` that knows them.
class ViewportNotifier extends Notifier<({Size size, double fitScale})> {
  @override
  ({Size size, double fitScale}) build() => (size: Size.zero, fitScale: 1);

  void set(Size size, double fitScale) {
    if (state.size != size || state.fitScale != fitScale) {
      state = (size: size, fitScale: fitScale);
    }
  }
}

final viewportProvider =
    NotifierProvider<ViewportNotifier, ({Size size, double fitScale})>(
      ViewportNotifier.new,
    );
