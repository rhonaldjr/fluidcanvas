import 'package:inkpad/domain/commands/command.dart';
import 'package:inkpad/domain/models/models.dart';

/// Wraps several of a layer's elements into one [Group].
///
/// The group takes the z-position of the **topmost** member, and the children
/// keep their relative order. Grouping is exact to undo: `revert` restores the
/// layer's element list verbatim rather than trying to reconstruct where each
/// child was.
///
/// A connector inside the group whose other end is bound to something left
/// outside is frozen where it stood: a group's connectors resolve against their
/// siblings, and that shape is no longer one.
class GroupElementsCommand extends Command {
  GroupElementsCommand({
    required this.layerId,
    required this.groupId,
    required Set<String> memberIds,
  }) : memberIds = Set.unmodifiable(memberIds),
       assert(memberIds.length >= 2, 'grouping needs at least two elements');

  final String layerId;
  final String groupId;
  final Set<String> memberIds;

  /// The layer's elements before the group was made. Captured on the first
  /// apply, so undo restores the exact list — and so a redo can rebuild it.
  List<CanvasElement>? _before;

  @override
  String get label => 'Group';

  @override
  SkdDocument apply(SkdDocument document) {
    final layer = _layer(document);
    _before ??= layer.elements;

    final members = <CanvasElement>[];
    final rest = <CanvasElement>[];
    var topIndex = -1;

    for (var i = 0; i < layer.elements.length; i++) {
      final element = layer.elements[i];
      if (memberIds.contains(element.id)) {
        members.add(element);
        topIndex = i;
      } else {
        rest.add(element);
      }
    }
    if (members.length < 2) {
      throw ArgumentError('grouping needs at least two elements in the layer');
    }

    // A connector that reaches outside the group can no longer follow what it
    // pointed at, so it stops following and stays put.
    final frozen = [
      for (final member in members)
        member is Connector
            ? freezeBindingsOutside(member, memberIds, layer.elements)
            : member,
    ];

    // How many non-members sit below the topmost member: where the group goes.
    final insertAt = layer.elements
        .take(topIndex + 1)
        .where((e) => !memberIds.contains(e.id))
        .length;

    final next = [...rest]
      ..insert(insertAt, Group(id: groupId, children: frozen));
    return document.replaceLayer(layer.copyWith(elements: next));
  }

  @override
  SkdDocument revert(SkdDocument document) =>
      document.replaceLayer(_layer(document).copyWith(elements: _before!));

  Layer _layer(SkdDocument document) {
    final layer = document.layerById(layerId);
    if (layer == null) {
      throw ArgumentError.value(layerId, 'layerId', 'no such layer');
    }
    return layer;
  }
}

/// Splices a group's children back into its layer, at the group's position.
///
/// One level only: ungrouping a group of groups leaves the inner groups intact,
/// which is what every editor does and what the user meant by nesting them.
class UngroupElementsCommand extends Command {
  UngroupElementsCommand({required this.layerId, required this.groupId});

  final String layerId;
  final String groupId;

  List<CanvasElement>? _before;

  @override
  String get label => 'Ungroup';

  @override
  SkdDocument apply(SkdDocument document) {
    final layer = _layer(document);
    _before ??= layer.elements;

    final at = layer.elements.indexWhere((e) => e.id == groupId);
    if (at == -1) {
      throw ArgumentError.value(groupId, 'groupId', 'no such element');
    }
    final group = layer.elements[at];
    if (group is! Group) {
      throw ArgumentError.value(groupId, 'groupId', 'not a group');
    }

    final next = [...layer.elements]
      ..removeAt(at)
      ..insertAll(at, group.children);
    return document.replaceLayer(layer.copyWith(elements: next));
  }

  @override
  SkdDocument revert(SkdDocument document) =>
      document.replaceLayer(_layer(document).copyWith(elements: _before!));

  Layer _layer(SkdDocument document) {
    final layer = document.layerById(layerId);
    if (layer == null) {
      throw ArgumentError.value(layerId, 'layerId', 'no such layer');
    }
    return layer;
  }
}
