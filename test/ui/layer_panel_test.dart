import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/ui.dart';

Future<ProviderContainer> pumpPanel(
  WidgetTester tester, {
  List<String> layerNames = const ['Layer 1'],
}) async {
  await tester.binding.setSurfaceSize(const Size(400, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final container = ProviderContainer.test();
  if (layerNames.length > 1) {
    container
        .read(sessionsProvider.notifier)
        .openSession(
          SkdDocument(
            canvasWidth: 1920,
            canvasHeight: 1080,
            layers: [
              for (final name in layerNames) Layer(id: name, name: name),
            ],
          ),
        );
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: Row(children: [LayerPanel()])),
      ),
    ),
  );
  return container;
}

SkdDocument docOf(ProviderContainer c) => c.read(activeDocumentProvider);
List<String> layerIds(ProviderContainer c) => [
  for (final l in docOf(c).layers) l.id,
];

void main() {
  group('reorderIndices', () {
    // The panel lists layers top-first; the document stores them bottom-first.
    test('flips the axis', () {
      expect(reorderIndices(3, 0, 2), (oldIndex: 2, newIndex: 0));
      expect(reorderIndices(3, 2, 0), (oldIndex: 0, newIndex: 2));
    });

    test('a no-op drag maps to a no-op move', () {
      expect(reorderIndices(3, 1, 1), (oldIndex: 1, newIndex: 1));
    });

    test('dragging the top row down one lands it one below the top', () {
      // Display [top, mid, bot] = model [bot, mid, top].
      // Moving display 0 -> 1 must move model 2 -> 1.
      expect(reorderIndices(3, 0, 1), (oldIndex: 2, newIndex: 1));
    });
  });

  group('7.1 panel', () {
    testWidgets('lists one tile per layer, topmost first', (tester) async {
      await pumpPanel(tester, layerNames: ['bottom', 'middle', 'top']);

      expect(find.byType(LayerTile), findsNWidgets(3));

      final tiles = tester
          .widgetList<LayerTile>(find.byType(LayerTile))
          .toList();
      expect([for (final t in tiles) t.layer.id], ['top', 'middle', 'bottom']);
    });

    testWidgets('the active layer is highlighted', (tester) async {
      final container = await pumpPanel(tester, layerNames: ['a', 'b']);
      // openSession activates the topmost layer.
      expect(container.read(activeSessionProvider).activeLayerId, 'b');

      final tiles = tester.widgetList<LayerTile>(find.byType(LayerTile));
      expect(tiles.firstWhere((t) => t.layer.id == 'b').selected, isTrue);
      expect(tiles.firstWhere((t) => t.layer.id == 'a').selected, isFalse);
    });

    testWidgets('tapping a tile selects that layer', (tester) async {
      final container = await pumpPanel(tester, layerNames: ['a', 'b']);

      // The tile's opacity slider covers its middle, so aim at the thumbnail.
      await tester.tap(find.byKey(const Key('layer-thumbnail-a')));
      await tester.pumpAndSettle();

      expect(container.read(activeSessionProvider).activeLayerId, 'a');
    });

    testWidgets('selecting a layer is not undoable', (tester) async {
      final container = await pumpPanel(tester, layerNames: ['a', 'b']);
      await tester.tap(find.byKey(const Key('layer-thumbnail-a')));
      await tester.pumpAndSettle();

      expect(container.read(activeSessionProvider).canUndo, isFalse);
    });

    testWidgets('the eye toggles visibility, undoably', (tester) async {
      final container = await pumpPanel(tester, layerNames: ['a', 'b']);
      expect(docOf(container).layerById('a')!.visible, isTrue);

      await tester.tap(find.byKey(const Key('layer-visibility-a')));
      await tester.pumpAndSettle();
      expect(docOf(container).layerById('a')!.visible, isFalse);

      container.read(sessionsProvider.notifier).undo();
      await tester.pumpAndSettle();
      expect(docOf(container).layerById('a')!.visible, isTrue);
    });
  });

  group('7.2 add and delete', () {
    testWidgets('add inserts a layer above the active one and selects it', (
      tester,
    ) async {
      final container = await pumpPanel(tester, layerNames: ['a', 'b']);
      container.read(sessionsProvider.notifier).setActiveLayer('a');
      await tester.pump();

      await tester.tap(find.byKey(const Key('add-layer')));
      await tester.pumpAndSettle();

      final ids = layerIds(container);
      expect(ids, hasLength(3));
      expect(ids.indexOf('a'), 0);
      expect(ids.indexOf('b'), 2);
      // The new layer sits between them, and is now active.
      expect(container.read(activeSessionProvider).activeLayerId, ids[1]);
    });

    testWidgets('adding a layer is undoable', (tester) async {
      final container = await pumpPanel(tester);
      await tester.tap(find.byKey(const Key('add-layer')));
      await tester.pumpAndSettle();
      expect(docOf(container).layerCount, 2);

      container.read(sessionsProvider.notifier).undo();
      await tester.pumpAndSettle();
      expect(docOf(container).layerCount, 1);
    });

    testWidgets('delete is disabled when only one layer remains', (
      tester,
    ) async {
      await pumpPanel(tester);
      final button = tester.widget<IconButton>(
        find.byKey(const Key('delete-layer')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('delete removes the active layer', (tester) async {
      final container = await pumpPanel(tester, layerNames: ['a', 'b']);
      container.read(sessionsProvider.notifier).setActiveLayer('a');
      await tester.pump();

      await tester.tap(find.byKey(const Key('delete-layer')));
      await tester.pumpAndSettle();

      expect(layerIds(container), ['b']);
      // The active layer went with it; the session falls back to a survivor.
      expect(container.read(activeSessionProvider).activeLayerId, 'b');
    });

    testWidgets('undoing a delete restores the layer and its strokes', (
      tester,
    ) async {
      final container = await pumpPanel(tester, layerNames: ['a', 'b']);
      final notifier = container.read(sessionsProvider.notifier)
        ..setActiveLayer('a')
        ..addElementToActiveLayer(
          Stroke(
            id: 's',
            colorRGBA: 0,
            baseWidth: 2,
            points: const [StrokePoint(x: 0, y: 0), StrokePoint(x: 9, y: 9)],
          ),
        );
      await tester.pump();

      await tester.tap(find.byKey(const Key('delete-layer')));
      await tester.pumpAndSettle();
      expect(layerIds(container), ['b']);

      notifier.undo();
      await tester.pumpAndSettle();
      expect(layerIds(container), ['a', 'b']);
      expect(docOf(container).layerById('a')!.elementCount, 1);
    });
  });

  group('7.4 opacity and rename', () {
    testWidgets('dragging opacity pushes exactly one command', (tester) async {
      final container = await pumpPanel(tester, layerNames: ['a', 'b']);

      await tester.drag(
        find.byKey(const Key('layer-opacity-a')),
        const Offset(-40, 0),
      );
      await tester.pumpAndSettle();

      final opacity = docOf(container).layerById('a')!.opacity;
      expect(opacity, lessThan(1.0));

      // One command, not one per pixel of the drag.
      container.read(sessionsProvider.notifier).undo();
      await tester.pumpAndSettle();
      expect(docOf(container).layerById('a')!.opacity, 1.0);
      expect(container.read(activeSessionProvider).canUndo, isFalse);
    });

    testWidgets('double-tapping a tile opens the rename dialog', (
      tester,
    ) async {
      final container = await pumpPanel(tester, layerNames: ['a', 'b']);

      await tester.tap(find.byKey(const Key('layer-name-a')));
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(find.byKey(const Key('layer-name-a')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('rename-field')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('rename-field')), 'Sketch');
      await tester.tap(find.byKey(const Key('rename-ok')));
      await tester.pumpAndSettle();

      expect(docOf(container).layerById('a')!.name, 'Sketch');

      container.read(sessionsProvider.notifier).undo();
      await tester.pump();
      expect(docOf(container).layerById('a')!.name, 'a');
    });

    testWidgets('an empty rename is ignored', (tester) async {
      final container = await pumpPanel(tester, layerNames: ['a', 'b']);

      await tester.tap(find.byKey(const Key('layer-name-a')));
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(find.byKey(const Key('layer-name-a')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('rename-field')), '   ');
      await tester.tap(find.byKey(const Key('rename-ok')));
      await tester.pumpAndSettle();

      expect(docOf(container).layerById('a')!.name, 'a');
      expect(container.read(activeSessionProvider).canUndo, isFalse);
    });
  });

  group('7.5 thumbnails', () {
    testWidgets('every layer shows a thumbnail box', (tester) async {
      await pumpPanel(tester, layerNames: ['a', 'b']);
      expect(find.byType(LayerThumbnail), findsNWidgets(2));
      expect(find.byKey(const Key('layer-thumbnail-a')), findsOneWidget);
    });

    testWidgets('an empty layer paints no thumbnail image', (tester) async {
      await pumpPanel(tester);
      final thumb = tester.widget<Container>(
        find.descendant(
          of: find.byType(LayerThumbnail),
          matching: find.byType(Container),
        ),
      );
      expect(thumb.child, isNull);
    });

    testWidgets('a layer with strokes paints one', (tester) async {
      final container = await pumpPanel(tester);
      container
          .read(sessionsProvider.notifier)
          .addElementToActiveLayer(
            Stroke(
              id: 's',
              colorRGBA: 0x000000FF,
              baseWidth: 20,
              points: const [
                StrokePoint(x: 10, y: 10),
                StrokePoint(x: 900, y: 500),
              ],
            ),
          );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(LayerThumbnail),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
      );
    });

    testWidgets('the thumbnail keeps the document aspect ratio', (
      tester,
    ) async {
      await pumpPanel(tester);
      final size = tester.getSize(
        find.byKey(const Key('layer-thumbnail-a')).evaluate().isEmpty
            ? find.byType(LayerThumbnail)
            : find.byType(LayerThumbnail),
      );
      expect(size.width / size.height, closeTo(1920 / 1080, 0.02));
      expect(size.width, kLayerThumbnailSize);
    });
  });

  group('7.3 reorder', () {
    testWidgets('dragging a row reorders the document, undoably', (
      tester,
    ) async {
      final container = await pumpPanel(
        tester,
        layerNames: ['bottom', 'middle', 'top'],
      );
      expect(layerIds(container), ['bottom', 'middle', 'top']);

      // Drag the topmost row (display 0) down past the next one.
      final handle = find.descendant(
        of: find.byKey(const Key('layer-tile-top')),
        matching: find.byIcon(Icons.drag_indicator),
      );
      // ReorderableDragStartListener starts on touch, and the list needs
      // incremental moves to track the drag.
      final tileHeight = tester
          .getSize(find.byKey(const Key('layer-tile-top')))
          .height;
      final start = tester.getCenter(handle);
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 20));
      for (var i = 1; i <= 10; i++) {
        await gesture.moveTo(start + Offset(0, tileHeight * 1.2 * i / 10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      // 'top' has dropped one place in the stack.
      expect(layerIds(container), ['bottom', 'top', 'middle']);

      container.read(sessionsProvider.notifier).undo();
      await tester.pumpAndSettle();
      expect(layerIds(container), ['bottom', 'middle', 'top']);
    });

    testWidgets('reordering leaves the active layer selected', (tester) async {
      final container = await pumpPanel(
        tester,
        layerNames: ['bottom', 'middle', 'top'],
      );
      final active = container.read(activeSessionProvider).activeLayerId;

      container.read(sessionsProvider.notifier).reorderLayers(2, 0);
      await tester.pumpAndSettle();

      expect(container.read(activeSessionProvider).activeLayerId, active);
      expect(layerIds(container), ['top', 'bottom', 'middle']);
    });

    testWidgets('a no-op reorder pushes no command', (tester) async {
      final container = await pumpPanel(tester, layerNames: ['a', 'b']);
      container.read(sessionsProvider.notifier).reorderLayers(1, 1);
      await tester.pump();
      expect(container.read(activeSessionProvider).canUndo, isFalse);
    });
  });
}
