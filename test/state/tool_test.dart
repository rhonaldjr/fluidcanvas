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

  test('the stroke tools map onto their wire toolId', () {
    // These numbers are written into .skd files.
    expect(Tool.pen.strokeToolId, ToolId.pen);
    expect(Tool.eraser.strokeToolId, ToolId.eraser);
    expect(Tool.pen.strokeToolId, 0);
    expect(Tool.eraser.strokeToolId, 1);
  });

  test('each shape tool names the shape it draws', () {
    expect(Tool.rectangle.shapeType, ShapeType.rectangle);
    expect(Tool.diamond.shapeType, ShapeType.diamond);
    expect(Tool.pen.shapeType, isNull);
  });

  test('select draws neither a stroke nor a shape', () {
    expect(Tool.select.drawsStroke, isFalse);
    expect(Tool.select.drawsShape, isFalse);
  });

  test('every tool draws at most one kind of thing', () {
    for (final tool in Tool.values) {
      expect(tool.drawsStroke && tool.drawsShape, isFalse, reason: tool.name);
    }
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
