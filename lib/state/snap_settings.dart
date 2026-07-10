import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/engine/snapping.dart';

/// Snapping, grid visibility and grid size.
///
/// Global rather than per-session, like the tool and the brush: switching tabs
/// must not change whether your next drag snaps.
class SnapSettings {
  const SnapSettings({
    this.snapToElements = true,
    this.snapToGrid = false,
    this.showGrid = false,
    this.gridSize = kDefaultGridSize,
  }) : assert(gridSize > 0, 'gridSize must be positive');

  final bool snapToElements;
  final bool snapToGrid;
  final bool showGrid;
  final double gridSize;

  /// The grid a snap should use, or `null` when it should ignore the grid.
  double? get activeGrid => snapToGrid ? gridSize : null;

  bool get anySnapping => snapToElements || snapToGrid;

  SnapSettings copyWith({
    bool? snapToElements,
    bool? snapToGrid,
    bool? showGrid,
    double? gridSize,
  }) => SnapSettings(
    snapToElements: snapToElements ?? this.snapToElements,
    snapToGrid: snapToGrid ?? this.snapToGrid,
    showGrid: showGrid ?? this.showGrid,
    gridSize: gridSize ?? this.gridSize,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SnapSettings &&
          snapToElements == other.snapToElements &&
          snapToGrid == other.snapToGrid &&
          showGrid == other.showGrid &&
          gridSize == other.gridSize;

  @override
  int get hashCode =>
      Object.hash(snapToElements, snapToGrid, showGrid, gridSize);
}

class SnapSettingsNotifier extends Notifier<SnapSettings> {
  @override
  SnapSettings build() => const SnapSettings();

  void set(SnapSettings value) => state = value;

  void toggleSnapToElements() =>
      state = state.copyWith(snapToElements: !state.snapToElements);

  /// Showing the grid turns snapping to it on; a visible grid you cannot land
  /// on is decoration.
  void toggleGrid() {
    final showing = !state.showGrid;
    state = state.copyWith(showGrid: showing, snapToGrid: showing);
  }

  void setGridSize(double size) =>
      state = state.copyWith(gridSize: size.clamp(2, 500));
}

final snapSettingsProvider =
    NotifierProvider<SnapSettingsNotifier, SnapSettings>(
      SnapSettingsNotifier.new,
    );

/// The guides to draw right now. Empty between drags.
class SnapGuidesNotifier extends Notifier<List<SnapGuide>> {
  @override
  List<SnapGuide> build() => const [];

  void set(List<SnapGuide> guides) {
    if (guides.isEmpty && state.isEmpty) return;
    state = guides;
  }

  void clear() => set(const []);
}

final snapGuidesProvider =
    NotifierProvider<SnapGuidesNotifier, List<SnapGuide>>(
      SnapGuidesNotifier.new,
    );
