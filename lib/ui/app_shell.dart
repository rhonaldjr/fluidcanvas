import 'package:flutter/material.dart';
import 'package:inkpad/ui/app_menu_bar.dart';
import 'package:inkpad/ui/canvas_view.dart';
import 'package:inkpad/ui/toolbar_strip.dart';

/// Top-level window layout: menu bar across the top, tool strip down the left,
/// canvas filling the rest. The tab strip slots between the menu bar and the
/// canvas in task 10.1; the layer panel lands to the right in task 7.1.
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
              // Without stretch the strip shrink-wraps its content and floats
              // vertically centred, leaving the scaffold showing above it.
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
