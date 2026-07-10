import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/ui.dart';

import '../support/test_container.dart';

const _pageKey = Key('canvas-page');

Future<ProviderContainer> pumpShell(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = testContainer();
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: AppShell()),
    ),
  );
  await tester.pump();
  return container;
}

Shape only(ProviderContainer c) => c
    .read(activeDocumentProvider)
    .layers
    .expand((l) => l.elements)
    .whereType<Shape>()
    .single;

/// Drags a shape of [tool] from [from] to [to], in page-local pixels.
Future<void> drawShape(
  WidgetTester tester,
  ProviderContainer c,
  Tool tool,
  Offset from,
  Offset to,
) async {
  c.read(toolProvider.notifier).select(tool);
  await tester.pump();
  final origin = tester.getRect(find.byKey(_pageKey)).topLeft;
  final gesture = await tester.startGesture(origin + from);
  await tester.pump();
  await gesture.moveTo(origin + to);
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an arrow drawn left-to-right runs rightward', (tester) async {
    final container = await pumpShell(tester);
    await drawShape(
      tester,
      container,
      Tool.arrow,
      const Offset(100, 100),
      const Offset(260, 140),
    );

    final arrow = only(container);
    expect(arrow.type, ShapeType.arrow);
    expect(arrow.w, greaterThan(0), reason: 'end is to the right of start');
    expect(arrow.h, greaterThan(0));
  });

  testWidgets('an arrow drawn right-to-left keeps its leftward direction', (
    tester,
  ) async {
    final container = await pumpShell(tester);
    // Anchor on the right, drag to the upper-left.
    await drawShape(
      tester,
      container,
      Tool.arrow,
      const Offset(260, 140),
      const Offset(100, 100),
    );

    final arrow = only(container);
    // The bug was that this came out pointing right (w folded positive). Now the
    // extent stays negative, so the head is at the drag end.
    expect(arrow.w, lessThan(0), reason: 'the arrow runs up-left');
    expect(arrow.h, lessThan(0));
    // The start is still where the drag began.
    expect(arrow.x, closeTo(260, 2));
    expect(arrow.y, closeTo(140, 2));
  });

  testWidgets('a line drawn upward keeps its negative extent', (tester) async {
    final container = await pumpShell(tester);
    await drawShape(
      tester,
      container,
      Tool.line,
      const Offset(200, 300),
      const Offset(120, 120),
    );

    final line = only(container);
    expect(line.type, ShapeType.line);
    expect(line.w, lessThan(0));
    expect(line.h, lessThan(0));
  });

  testWidgets('a rectangle drawn up-left is still normalized', (tester) async {
    final container = await pumpShell(tester);
    await drawShape(
      tester,
      container,
      Tool.rectangle,
      const Offset(260, 200),
      const Offset(100, 100),
    );

    final rect = only(container);
    expect(rect.type, ShapeType.rectangle);
    expect(rect.w, greaterThan(0), reason: 'boxes fold their sign');
    expect(rect.h, greaterThan(0));
  });
}
