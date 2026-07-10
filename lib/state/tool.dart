import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/domain/models/models.dart';

/// The active tool.
///
/// Global, like the brush: switching tabs must not change the tool in your
/// hand.
enum Tool {
  select(),
  pen(strokeToolId: ToolId.pen),
  eraser(strokeToolId: ToolId.eraser),
  rectangle(shapeType: ShapeType.rectangle),
  ellipse(shapeType: ShapeType.ellipse),
  line(shapeType: ShapeType.line),
  arrow(shapeType: ShapeType.arrow),
  diamond(shapeType: ShapeType.diamond),
  text(),
  connector();

  const Tool({this.strokeToolId, this.shapeType});

  /// The `u8` written into the `.skd` element blob, for the tools that draw
  /// strokes. `null` for the others.
  final int? strokeToolId;

  /// The shape this tool draws, or `null` when it draws none.
  final ShapeType? shapeType;

  bool get drawsStroke => strokeToolId != null;
  bool get drawsShape => shapeType != null;
  bool get drawsText => this == Tool.text;
  bool get drawsConnector => this == Tool.connector;
}

class ToolNotifier extends Notifier<Tool> {
  @override
  Tool build() => Tool.pen;

  void select(Tool tool) => state = tool;
}

final toolProvider = NotifierProvider<ToolNotifier, Tool>(ToolNotifier.new);
