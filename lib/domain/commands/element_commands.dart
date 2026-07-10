import 'package:inkpad/domain/commands/command.dart';
import 'package:inkpad/domain/models/models.dart';

/// Adds one element to the top of a layer. The commit path of every drawing
/// tool ends here.
class AddElementCommand extends Command {
  const AddElementCommand({required this.layerId, required this.element});

  final String layerId;
  final CanvasElement element;

  @override
  String get label => element is Stroke ? 'Draw' : 'Add Shape';

  @override
  SkdDocument apply(SkdDocument document) {
    final layer = document.layerById(layerId);
    if (layer == null) {
      throw ArgumentError.value(layerId, 'layerId', 'no such layer');
    }
    return document.replaceLayer(layer.addElement(element));
  }

  @override
  SkdDocument revert(SkdDocument document) {
    final layer = document.layerById(layerId);
    if (layer == null) {
      throw ArgumentError.value(layerId, 'layerId', 'no such layer');
    }
    return document.replaceLayer(layer.removeElement(element.id));
  }
}
