import 'package:flutter/material.dart';
import 'package:inkpad/ui/app_menu_bar.dart';
import 'package:inkpad/ui/canvas_view.dart';
import 'package:inkpad/ui/toolbar_strip.dart';

/// Top-level window layout: menu bar across the top, tool strip down the left,
/// canvas filling the rest. The layer panel lands to the right in Phase 6.1.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Column(
        children: [
          AppMenuBar(),
          Expanded(
            child: Row(
              children: [
                ToolbarStrip(),
                Expanded(child: CanvasView()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
