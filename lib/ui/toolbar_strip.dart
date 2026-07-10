import 'package:flutter/material.dart';

/// Width of the left tool strip, in screen pixels.
const double kToolbarStripWidth = 48;

/// The left tool strip. Empty until task 4.2 adds brush controls and
/// task 8.1 adds the shape tools.
class ToolbarStrip extends StatelessWidget {
  const ToolbarStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const Key('toolbar-strip'),
      width: kToolbarStripWidth,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: theme.dividerColor)),
      ),
    );
  }
}
