import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/ui/ui.dart';

// CanvasView reads the active document, so the shell needs a ProviderScope.
const _docWidth = 1920.0;
const _docHeight = 1080.0;

const _pageFinder = Key('canvas-page');

Future<void> _pumpShell(
  WidgetTester tester, {
  Size size = const Size(1280, 720),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    const ProviderScope(child: MaterialApp(home: AppShell())),
  );
}

void main() {
  testWidgets('shows File and Edit menus', (tester) async {
    await _pumpShell(tester);

    expect(find.byType(MenuBar), findsOneWidget);
    expect(find.text('File'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('menus are left-aligned, not centered', (tester) async {
    await _pumpShell(tester);

    // File sits at the far left, Edit immediately to its right.
    final file = tester.getRect(find.text('File'));
    final edit = tester.getRect(find.text('Edit'));
    expect(file.left, lessThan(64));
    expect(edit.left, greaterThan(file.right));
  });

  testWidgets('menu items are present but disabled', (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();

    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Export PNG…'), findsOneWidget);

    final items = tester.widgetList<MenuItemButton>(
      find.byType(MenuItemButton),
    );
    expect(items, isNotEmpty);
    for (final item in items) {
      expect(
        item.onPressed,
        isNull,
        reason: 'menu items must have no action yet',
      );
    }
  });

  testWidgets('the toolbar strip spans the full height below the menu bar', (
    tester,
  ) async {
    await _pumpShell(tester);

    final strip = tester.getRect(find.byKey(const Key('toolbar-strip')));
    final canvas = tester.getRect(find.byType(CanvasView));
    expect(strip.top, closeTo(canvas.top, 0.5));
    expect(strip.bottom, closeTo(canvas.bottom, 0.5));
  });

  testWidgets('left toolbar strip holds the brush controls', (tester) async {
    await _pumpShell(tester);

    final strip = find.byKey(const Key('toolbar-strip'));
    expect(strip, findsOneWidget);
    expect(tester.getSize(strip).width, kToolbarStripWidth);
    expect(
      find.descendant(of: strip, matching: find.byType(BrushWidthControl)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: strip, matching: find.byType(ColorSwatches)),
      findsOneWidget,
    );
  });

  testWidgets('page keeps a 1920x1080 aspect ratio and fits the viewport', (
    tester,
  ) async {
    await _pumpShell(tester);

    final viewport = tester.getSize(find.byType(CanvasView));
    final page = tester.getSize(find.byKey(_pageFinder));

    expect(page.width / page.height, closeTo(_docWidth / _docHeight, 0.001));
    expect(page.width, lessThanOrEqualTo(viewport.width));
    expect(page.height, lessThanOrEqualTo(viewport.height));

    // The page is scaled to fit, so one axis is snug against the 32px margin.
    final expected = math.min(
      (viewport.width - 64) / _docWidth,
      (viewport.height - 64) / _docHeight,
    );
    expect(page.width, closeTo(_docWidth * expected, 0.5));
  });

  testWidgets('page is centered in the canvas area', (tester) async {
    await _pumpShell(tester);

    final viewport = tester.getRect(find.byType(CanvasView));
    final page = tester.getRect(find.byKey(_pageFinder));

    expect(page.center.dx, closeTo(viewport.center.dx, 0.5));
    expect(page.center.dy, closeTo(viewport.center.dy, 0.5));
  });

  testWidgets('page is never magnified past 100%', (tester) async {
    await _pumpShell(tester, size: const Size(4000, 3000));

    final page = tester.getSize(find.byKey(_pageFinder));
    expect(page.width, _docWidth);
    expect(page.height, _docHeight);
  });

  testWidgets('page collapses rather than going negative when the viewport is '
      'smaller than the margins', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Center(
            child: SizedBox(width: 50, height: 50, child: CanvasView()),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(_pageFinder)), Size.zero);
  });
}
