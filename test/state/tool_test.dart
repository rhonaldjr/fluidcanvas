import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/state/state.dart';

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer.test());

  test('defaults to the pen', () {
    expect(container.read(toolProvider), Tool.pen);
  });

  test('each tool maps onto its wire toolId', () {
    // These numbers are written into .skd files.
    expect(Tool.pen.toolId, ToolId.pen);
    expect(Tool.eraser.toolId, ToolId.eraser);
    expect(Tool.pen.toolId, 0);
    expect(Tool.eraser.toolId, 1);
  });

  test('select switches the tool', () {
    container.read(toolProvider.notifier).select(Tool.eraser);
    expect(container.read(toolProvider), Tool.eraser);
  });

  test('selecting the same tool twice is harmless', () {
    container.read(toolProvider.notifier)
      ..select(Tool.eraser)
      ..select(Tool.eraser);
    expect(container.read(toolProvider), Tool.eraser);
  });
}
