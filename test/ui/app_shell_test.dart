import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/ui/ui.dart';

const _pageFinder = Key('canvas-page');

Future<void> _pumpShell(
  WidgetTester tester, {
  Size size = const Size(1280, 720),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const MaterialApp(home: AppShell()));
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

  testWidgets('left toolbar strip is present and empty', (tester) async {
    await _pumpShell(tester);

    final strip = find.byKey(const Key('toolbar-strip'));
    expect(strip, findsOneWidget);
    expect(tester.getSize(strip).width, kToolbarStripWidth);
    expect(
      find.descendant(of: strip, matching: find.byType(Widget)),
      findsNothing,
      reason: 'the strip holds no tools yet',
    );
  });

  testWidgets('page keeps a 1920x1080 aspect ratio and fits the viewport', (
    tester,
  ) async {
    await _pumpShell(tester);

    final viewport = tester.getSize(find.byType(CanvasView));
    final page = tester.getSize(find.byKey(_pageFinder));

    expect(
      page.width / page.height,
      closeTo(kDefaultCanvasWidth / kDefaultCanvasHeight, 0.001),
    );
    expect(page.width, lessThanOrEqualTo(viewport.width));
    expect(page.height, lessThanOrEqualTo(viewport.height));

    // The page is scaled to fit, so one axis is snug against the 32px margin.
    final expected = math.min(
      (viewport.width - 64) / kDefaultCanvasWidth,
      (viewport.height - 64) / kDefaultCanvasHeight,
    );
    expect(page.width, closeTo(kDefaultCanvasWidth * expected, 0.5));
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
    expect(page.width, kDefaultCanvasWidth);
    expect(page.height, kDefaultCanvasHeight);
  });

  testWidgets('page collapses rather than going negative when the viewport is '
      'smaller than the margins', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(width: 50, height: 50, child: CanvasView()),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byKey(_pageFinder)), Size.zero);
  });
}
