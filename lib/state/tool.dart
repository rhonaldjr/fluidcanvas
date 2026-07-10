import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/domain/models/models.dart';

/// The active drawing tool.
///
/// Global, like the brush: switching tabs must not change the tool in your
/// hand. Task 8.1 widens this to the shape tools and `select`.
enum Tool {
  pen(ToolId.pen),
  eraser(ToolId.eraser);

  const Tool(this.toolId);

  /// The `u8` written into the `.skd` element blob.
  final int toolId;
}

class ToolNotifier extends Notifier<Tool> {
  @override
  Tool build() => Tool.pen;

  void select(Tool tool) => state = tool;
}

final toolProvider = NotifierProvider<ToolNotifier, Tool>(ToolNotifier.new);
