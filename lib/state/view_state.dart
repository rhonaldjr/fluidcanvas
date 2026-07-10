import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The scale the page is currently drawn at: page screen size divided by
/// document size.
///
/// Published by the canvas so the status bar can read it without reaching into
/// the widget tree. Task 14.1 folds this into the session's viewport transform.
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
