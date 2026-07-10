import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/commands/commands.dart';
import 'package:inkpad/domain/models/models.dart';

Shape shapeAt(String id, double x, double y) => Shape(
  id: id,
  type: ShapeType.rectangle,
  x: x,
  y: y,
  w: 100,
  h: 100,
  strokeColorRGBA: 0xFF,
  strokeWidth: 2,
);

Connector bound(String id, String from, String to) => Connector(
  id: id,
  start: ConnectorEnd.bound(from),
  end: ConnectorEnd.bound(to),
  strokeColorRGBA: 0xFF,
  strokeWidth: 2,
);

/// A one-layer document holding [elements].
SkdDocument docOf(List<CanvasElement> elements) {
  final blank = SkdDocument.newDefault(layerId: 'L');
  return blank.replaceLayer(blank.layers.first.copyWith(elements: elements));
}

List<CanvasElement> elementsOf(SkdDocument document) =>
    document.layers.first.elements;

void main() {
  final a = shapeAt('a', 0, 0);
  final b = shapeAt('b', 200, 0);
  final c = shapeAt('c', 400, 0);

  group('17.3 the model', () {
    test('a group of fewer than two is a bug', () {
      expect(
        () => Group(id: 'g', children: [a]),
        throwsA(isA<AssertionError>()),
      );
    });

    test('its bounds are the union of its children', () {
      final group = Group(id: 'g', children: [a, b]);
      expect(
        group.bounds,
        const Bounds(left: 0, top: 0, right: 300, bottom: 100),
      );
    });

    test('leaves flattens nested groups, and lists no groups', () {
      final inner = Group(id: 'inner', children: [b, c]);
      final outer = Group(id: 'outer', children: [a, inner]);

      expect(outer.leaves.map((e) => e.id), ['a', 'b', 'c']);
      expect(outer.children, hasLength(2));
    });

    test('idsWithin names the group and everything under it', () {
      final inner = Group(id: 'inner', children: [b, c]);
      final outer = Group(id: 'outer', children: [a, inner]);
      expect(outer.idsWithin, {'outer', 'a', 'inner', 'b', 'c'});
    });

    test('moving a group moves every child', () {
      final moved = Group(id: 'g', children: [a, b]).translated(10, 20);
      expect((moved.children.first as Shape).x, 10);
      expect((moved.children.last as Shape).y, 20);
    });

    test('rotating a group turns it as one rigid body', () {
      // A quarter turn about the origin sends (200, 0) to (0, 200).
      final turned = Group(
        id: 'g',
        children: [a, b],
      ).rotated(3.14159265358979 / 2, originX: 0, originY: 0);

      final moved = turned.children.last as Shape;
      expect(moved.centerX, closeTo(-50, 0.001));
      expect(moved.centerY, closeTo(250, 0.001));
      // The child carries the angle: a group has no rotation field of its own.
      expect(moved.rotation, closeTo(3.14159265358979 / 2, 0.001));
    });

    test('scaling a group scales every child about the same origin', () {
      final scaled = Group(id: 'g', children: [a, b]).scaled(2);
      expect((scaled.children.last as Shape).x, 400);
      expect((scaled.children.last as Shape).strokeWidth, 4);
    });

    test('a group is equal to another with the same children', () {
      expect(
        Group(id: 'g', children: [a, b]),
        Group(id: 'g', children: [a, b]),
      );
      expect(
        Group(id: 'g', children: [a, b]),
        isNot(Group(id: 'g', children: [a, c])),
      );
    });
  });

  group('17.3 grouping', () {
    test('the group takes the topmost member\'s z-position', () {
      final document = docOf([a, b, c]);
      final grouped = GroupElementsCommand(
        layerId: 'L',
        groupId: 'g',
        memberIds: {'a', 'c'},
      ).apply(document);

      // b stays below; the group sits where c was, on top.
      expect(elementsOf(grouped).map((e) => e.id), ['b', 'g']);
      final group = elementsOf(grouped).last as Group;
      expect(group.children.map((e) => e.id), ['a', 'c']);
    });

    test('children keep their relative order', () {
      final document = docOf([a, b, c]);
      final grouped = GroupElementsCommand(
        layerId: 'L',
        groupId: 'g',
        memberIds: {'c', 'a', 'b'},
      ).apply(document);

      final group = elementsOf(grouped).single as Group;
      expect(group.children.map((e) => e.id), ['a', 'b', 'c']);
    });

    test('undo restores the layer exactly', () {
      final document = docOf([a, b, c]);
      final command = GroupElementsCommand(
        layerId: 'L',
        groupId: 'g',
        memberIds: {'a', 'c'},
      );
      final reverted = command.revert(command.apply(document));
      expect(elementsOf(reverted), elementsOf(document));
    });

    test('a redo rebuilds the same group', () {
      final document = docOf([a, b, c]);
      final command = GroupElementsCommand(
        layerId: 'L',
        groupId: 'g',
        memberIds: {'a', 'c'},
      );
      final once = command.apply(document);
      final twice = command.apply(command.revert(once));
      expect(elementsOf(twice), elementsOf(once));
    });

    test('a connector wholly inside the group stays bound', () {
      final connector = bound('x', 'a', 'b');
      final document = docOf([a, b, connector]);
      final grouped = GroupElementsCommand(
        layerId: 'L',
        groupId: 'g',
        memberIds: {'a', 'b', 'x'},
      ).apply(document);

      final group = elementsOf(grouped).single as Group;
      final inside = group.children.last as Connector;
      expect(inside.start, const ConnectorEnd.bound('a'));
      expect(inside.end, const ConnectorEnd.bound('b'));
    });

    test('a connector reaching outside the group is frozen where it stood', () {
      final connector = bound('x', 'a', 'b');
      final document = docOf([a, b, connector]);
      final line = resolveConnector(connector, elementsOf(document));

      // 'b' is left outside.
      final grouped = GroupElementsCommand(
        layerId: 'L',
        groupId: 'g',
        memberIds: {'a', 'x'},
      ).apply(document);

      final group = elementsOf(grouped).last as Group;
      final inside = group.children.last as Connector;

      expect(inside.start, const ConnectorEnd.bound('a'));
      expect(inside.end.isBound, isFalse);
      expect(inside.end.x, closeTo(line.x2, 0.001));
    });

    test('grouping fewer than two elements is refused', () {
      expect(
        () =>
            GroupElementsCommand(layerId: 'L', groupId: 'g', memberIds: {'a'}),
        throwsA(isA<AssertionError>()),
      );
    });

    test('an unknown layer throws', () {
      expect(
        () => GroupElementsCommand(
          layerId: 'nope',
          groupId: 'g',
          memberIds: {'a', 'b'},
        ).apply(docOf([a, b])),
        throwsArgumentError,
      );
    });
  });

  group('17.3 ungrouping', () {
    test('children come back where the group was', () {
      final document = docOf([
        shapeAt('z', 900, 900),
        Group(id: 'g', children: [a, b]),
      ]);
      final ungrouped = UngroupElementsCommand(
        layerId: 'L',
        groupId: 'g',
      ).apply(document);

      expect(elementsOf(ungrouped).map((e) => e.id), ['z', 'a', 'b']);
    });

    test('undo puts the group back', () {
      final document = docOf([
        Group(id: 'g', children: [a, b]),
      ]);
      final command = UngroupElementsCommand(layerId: 'L', groupId: 'g');
      final reverted = command.revert(command.apply(document));
      expect(elementsOf(reverted), elementsOf(document));
    });

    test('one level only: an inner group survives', () {
      final inner = Group(id: 'inner', children: [b, c]);
      final document = docOf([
        Group(id: 'outer', children: [a, inner]),
      ]);

      final ungrouped = UngroupElementsCommand(
        layerId: 'L',
        groupId: 'outer',
      ).apply(document);

      expect(elementsOf(ungrouped).map((e) => e.id), ['a', 'inner']);
      expect(elementsOf(ungrouped).last, isA<Group>());
    });

    test('ungrouping something that is not a group throws', () {
      expect(
        () => UngroupElementsCommand(
          layerId: 'L',
          groupId: 'a',
        ).apply(docOf([a, b])),
        throwsArgumentError,
      );
    });

    test('ungrouping a missing element throws', () {
      expect(
        () => UngroupElementsCommand(
          layerId: 'L',
          groupId: 'nope',
        ).apply(docOf([a, b])),
        throwsArgumentError,
      );
    });
  });

  group('17.3 group + ungroup is a round trip', () {
    test('the layer is exactly as it was', () {
      final document = docOf([a, b, c]);
      final grouped = GroupElementsCommand(
        layerId: 'L',
        groupId: 'g',
        memberIds: {'a', 'b'},
      ).apply(document);

      // The group took b's z-position, so it sits below c.
      expect(elementsOf(grouped).map((e) => e.id), ['g', 'c']);

      final back = UngroupElementsCommand(
        layerId: 'L',
        groupId: 'g',
      ).apply(grouped);

      // Exactly the list we started with, elements and order alike.
      expect(elementsOf(back), elementsOf(document));
    });
  });
}
