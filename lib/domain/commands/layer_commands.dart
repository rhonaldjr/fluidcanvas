import 'package:inkpad/domain/commands/command.dart';
import 'package:inkpad/domain/models/models.dart';

/// Inserts a layer at [index], counting from the bottom.
class AddLayerCommand extends Command {
  const AddLayerCommand({required this.layer, required this.index});

  final Layer layer;
  final int index;

  @override
  String get label => 'Add Layer';

  @override
  SkdDocument apply(SkdDocument document) => document.insertLayer(index, layer);

  @override
  SkdDocument revert(SkdDocument document) => document.removeLayer(layer.id);
}

/// Removes a layer, remembering it and its position so [revert] can put it
/// back. Deleting the only layer of a document is disallowed.
class DeleteLayerCommand extends Command {
  const DeleteLayerCommand({required this.layer, required this.index});

  /// Captured before deletion: `revert` has no other way to restore its
  /// contents.
  final Layer layer;
  final int index;

  @override
  String get label => 'Delete Layer';

  @override
  SkdDocument apply(SkdDocument document) => document.removeLayer(layer.id);

  @override
  SkdDocument revert(SkdDocument document) =>
      document.insertLayer(index, layer);
}

/// Moves a layer within the stack. Indices address the resulting list.
class ReorderLayerCommand extends Command {
  const ReorderLayerCommand({required this.oldIndex, required this.newIndex});

  final int oldIndex;
  final int newIndex;

  @override
  String get label => 'Reorder Layers';

  @override
  SkdDocument apply(SkdDocument document) =>
      document.moveLayer(oldIndex, newIndex);

  @override
  SkdDocument revert(SkdDocument document) =>
      document.moveLayer(newIndex, oldIndex);
}

/// Renames a layer. Carries the old name so it can be put back.
class RenameLayerCommand extends Command {
  const RenameLayerCommand({
    required this.layerId,
    required this.oldName,
    required this.newName,
  });

  final String layerId;
  final String oldName;
  final String newName;

  @override
  String get label => 'Rename Layer';

  @override
  SkdDocument apply(SkdDocument document) => _rename(document, newName);

  @override
  SkdDocument revert(SkdDocument document) => _rename(document, oldName);

  SkdDocument _rename(SkdDocument document, String name) {
    final layer = document.layerById(layerId);
    if (layer == null) {
      throw ArgumentError.value(layerId, 'layerId', 'no such layer');
    }
    return document.replaceLayer(layer.copyWith(name: name));
  }
}

/// Changes a layer's opacity. Carries the old value so it can be put back.
class SetLayerOpacityCommand extends Command {
  const SetLayerOpacityCommand({
    required this.layerId,
    required this.oldOpacity,
    required this.newOpacity,
  });

  final String layerId;
  final double oldOpacity;
  final double newOpacity;

  @override
  String get label => 'Change Layer Opacity';

  @override
  SkdDocument apply(SkdDocument document) => _setOpacity(document, newOpacity);

  @override
  SkdDocument revert(SkdDocument document) => _setOpacity(document, oldOpacity);

  SkdDocument _setOpacity(SkdDocument document, double opacity) {
    final layer = document.layerById(layerId);
    if (layer == null) {
      throw ArgumentError.value(layerId, 'layerId', 'no such layer');
    }
    return document.replaceLayer(layer.copyWith(opacity: opacity));
  }
}

/// Shows or hides a layer.
class SetLayerVisibilityCommand extends Command {
  const SetLayerVisibilityCommand({
    required this.layerId,
    required this.visible,
  });

  final String layerId;
  final bool visible;

  @override
  String get label => visible ? 'Show Layer' : 'Hide Layer';

  @override
  SkdDocument apply(SkdDocument document) => _setVisible(document, visible);

  @override
  SkdDocument revert(SkdDocument document) => _setVisible(document, !visible);

  SkdDocument _setVisible(SkdDocument document, bool value) {
    final layer = document.layerById(layerId);
    if (layer == null) {
      throw ArgumentError.value(layerId, 'layerId', 'no such layer');
    }
    return document.replaceLayer(layer.copyWith(visible: value));
  }
}
