import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How many recent colours the toolbar remembers.
const int kMaxRecentColors = 8;

/// Colours picked from the custom-colour dialog, most recent first.
///
/// Global, like the brush: the palette follows you between tabs.
class RecentColorsNotifier extends Notifier<List<int>> {
  @override
  List<int> build() => const [];

  /// Moves [colorRGBA] to the front, dropping the oldest past
  /// [kMaxRecentColors].
  ///
  /// Re-picking a colour already in the list promotes it rather than
  /// duplicating it, so the row never shows the same swatch twice.
  void add(int colorRGBA) {
    state = [
      colorRGBA,
      ...state.where((c) => c != colorRGBA),
    ].take(kMaxRecentColors).toList(growable: false);
  }

  void clear() => state = const [];
}

final recentColorsProvider = NotifierProvider<RecentColorsNotifier, List<int>>(
  RecentColorsNotifier.new,
);
