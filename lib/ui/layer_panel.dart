import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/renderer/layer_cache.dart'
    show layerHasText, paintElement;
import 'package:inkpad/state/state.dart';

/// Width of the right-hand layer panel, in screen pixels.
const double kLayerPanelWidth = 232;

/// Longest edge of a layer thumbnail, in screen pixels.
const double kLayerThumbnailSize = 48;

/// Converts a drag in the panel — which lists layers **top first** — into the
/// bottom-first indices the document uses.
///
/// Both indices address the resulting list. `onReorderItem` has already
/// corrected the off-by-one that `onReorder` leaves for moves downward, so this
/// only has to flip the axis. Kept as a function, and tested, rather than left
/// inline in a callback.
({int oldIndex, int newIndex}) reorderIndices(
  int layerCount,
  int oldDisplayIndex,
  int newDisplayIndex,
) => (
  oldIndex: layerCount - 1 - oldDisplayIndex,
  newIndex: layerCount - 1 - newDisplayIndex,
);

/// The right-hand panel: layers listed top to bottom, as they stack.
class LayerPanel extends ConsumerWidget {
  const LayerPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(activeSessionProvider);
    final layers = session.document.layers;
    final notifier = ref.read(sessionsProvider.notifier);

    return Container(
      key: const Key('layer-panel'),
      width: kLayerPanelWidth,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(left: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelHeader(canDelete: layers.length > 1),
          Expanded(
            child: ReorderableListView.builder(
              key: const Key('layer-list'),
              buildDefaultDragHandles: false,
              itemCount: layers.length,
              onReorderItem: (oldDisplay, newDisplay) {
                final moved = reorderIndices(
                  layers.length,
                  oldDisplay,
                  newDisplay,
                );
                notifier.reorderLayers(moved.oldIndex, moved.newIndex);
              },
              itemBuilder: (context, displayIndex) {
                // The panel lists the topmost layer first; the document stores
                // them bottom first.
                final layer = layers[layers.length - 1 - displayIndex];
                return LayerTile(
                  key: ValueKey(layer.id),
                  layer: layer,
                  displayIndex: displayIndex,
                  selected: layer.id == session.activeLayerId,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelHeader extends ConsumerWidget {
  const _PanelHeader({required this.canDelete});

  final bool canDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(sessionsProvider.notifier);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(child: Text('Layers', style: theme.textTheme.titleSmall)),
          IconButton(
            key: const Key('add-layer'),
            tooltip: 'Add layer',
            icon: const Icon(Icons.add),
            onPressed: notifier.addLayer,
          ),
          IconButton(
            key: const Key('delete-layer'),
            tooltip: canDelete ? 'Delete layer' : 'A document needs one layer',
            icon: const Icon(Icons.delete_outline),
            // Deleting the last layer is disallowed, so the button goes dead
            // rather than throwing when pressed.
            onPressed: canDelete
                ? () => notifier.deleteLayer(
                    ref.read(activeSessionProvider).activeLayerId,
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// One row: thumbnail, name, visibility toggle, opacity slider.
class LayerTile extends ConsumerStatefulWidget {
  const LayerTile({
    required this.layer,
    required this.displayIndex,
    required this.selected,
    super.key,
  });

  final Layer layer;
  final int displayIndex;
  final bool selected;

  @override
  ConsumerState<LayerTile> createState() => _LayerTileState();
}

class _LayerTileState extends ConsumerState<LayerTile> {
  /// The opacity being dragged, before it is committed.
  ///
  /// A slider fires per pixel; pushing a command each time would bury the undo
  /// stack under hundreds of entries. One command per drag, on release.
  double? _draggingOpacity;

  Future<void> _rename() async {
    final controller = TextEditingController(text: widget.layer.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename layer'),
        content: TextField(
          key: const Key('rename-field'),
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('rename-ok'),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    ref.read(sessionsProvider.notifier).renameLayer(widget.layer.id, trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notifier = ref.read(sessionsProvider.notifier);
    final layer = widget.layer;
    final opacity = _draggingOpacity ?? layer.opacity;

    return Material(
      key: Key('layer-tile-${layer.id}'),
      color: widget.selected
          ? theme.colorScheme.primaryContainer
          : Colors.transparent,
      child: InkWell(
        // Double-click to rename is scoped to the name below, not the whole
        // row: an `onDoubleTap` here wins the gesture arena and swallows taps
        // meant for the visibility button and the opacity slider.
        onTap: () => notifier.setActiveLayer(layer.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: widget.displayIndex,
                child: const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.drag_indicator, size: 18),
                ),
              ),
              LayerThumbnail(layer: layer),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      key: Key('layer-name-${layer.id}'),
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: _rename,
                      child: Text(
                        layer.name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    SizedBox(
                      height: 24,
                      child: Slider(
                        key: Key('layer-opacity-${layer.id}'),
                        value: opacity,
                        onChanged: (value) =>
                            setState(() => _draggingOpacity = value),
                        onChangeEnd: (value) {
                          setState(() => _draggingOpacity = null);
                          notifier.setLayerOpacity(layer.id, value);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                key: Key('layer-visibility-${layer.id}'),
                tooltip: layer.visible ? 'Hide layer' : 'Show layer',
                iconSize: 18,
                icon: Icon(
                  layer.visible ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () => notifier.toggleLayerVisibility(layer.id),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A live thumbnail of one layer.
///
/// Blits the layer's cached image rather than re-rendering its strokes, so it
/// costs a scaled image draw and needs no throttling: the image only changes
/// when the layer's elements do.
class LayerThumbnail extends ConsumerWidget {
  const LayerThumbnail({required this.layer, super.key});

  final Layer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(activeDocumentProvider);
    final cache = ref.watch(layerCacheProvider);

    final aspect = document.canvasWidth / document.canvasHeight;
    final width = aspect >= 1
        ? kLayerThumbnailSize
        : kLayerThumbnailSize * aspect;
    final height = aspect >= 1
        ? kLayerThumbnailSize / aspect
        : kLayerThumbnailSize;

    return Container(
      key: Key('layer-thumbnail-${layer.id}'),
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: layer.isEmpty
          ? null
          : CustomPaint(
              // Text does not survive the toImageSync cache, so a layer with
              // any text is drawn live in the thumbnail too.
              painter: layerHasText(layer)
                  ? _LiveThumbnailPainter(
                      layer: layer,
                      documentWidth: document.canvasWidth,
                      documentHeight: document.canvasHeight,
                      opacity: layer.visible ? layer.opacity : 0.25,
                    )
                  : _ThumbnailPainter(
                      image: cache.imageFor(
                        layer,
                        width: document.canvasWidth,
                        height: document.canvasHeight,
                      ),
                      opacity: layer.visible ? layer.opacity : 0.25,
                    ),
            ),
    );
  }
}

/// Draws a layer's elements straight into the thumbnail, for layers whose text
/// the cached image would drop.
class _LiveThumbnailPainter extends CustomPainter {
  const _LiveThumbnailPainter({
    required this.layer,
    required this.documentWidth,
    required this.documentHeight,
    required this.opacity,
  });

  final Layer layer;
  final int documentWidth;
  final int documentHeight;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (documentWidth <= 0) return;
    canvas
      ..saveLayer(
        Offset.zero & size,
        Paint()..color = Color.fromARGB((opacity * 255).round(), 0, 0, 0),
      )
      ..scale(size.width / documentWidth);
    for (final element in layer.elements) {
      paintElement(canvas, element, siblings: layer.elements);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LiveThumbnailPainter old) =>
      !identical(old.layer.elements, layer.elements) ||
      old.opacity != opacity ||
      old.documentWidth != documentWidth ||
      old.documentHeight != documentHeight;
}

class _ThumbnailPainter extends CustomPainter {
  const _ThumbnailPainter({required this.image, required this.opacity});

  final ui.Image image;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()
        ..color = Color.fromARGB((opacity * 255).round(), 0, 0, 0)
        ..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_ThumbnailPainter old) =>
      !identical(old.image, image) || old.opacity != opacity;
}
