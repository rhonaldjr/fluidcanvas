import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/app_menu_bar.dart';
import 'package:inkpad/ui/canvas_view.dart';
import 'package:inkpad/ui/layer_panel.dart';
import 'package:inkpad/ui/toolbar_strip.dart';

/// Top-level window layout: menu bar across the top, tool strip down the left,
/// canvas filling the rest. The tab strip slots between the menu bar and the
/// canvas in task 10.1; the layer panel lands to the right in task 7.1.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.read(sessionsProvider.notifier);

    // Shortcuts live above the shell so they fire wherever focus sits, and
    // `autofocus` gives the canvas focus at startup so the first Ctrl+Z works
    // without clicking anything first.
    return Shortcuts(
      shortcuts: kUndoRedoShortcuts,
      child: Actions(
        actions: {
          UndoIntent: CallbackAction<UndoIntent>(
            onInvoke: (_) => sessions.undo(),
          ),
          RedoIntent: CallbackAction<RedoIntent>(
            onInvoke: (_) => sessions.redo(),
          ),
        },
        child: const Focus(
          autofocus: true,
          child: Scaffold(
            body: Column(
              children: [
                AppMenuBar(),
                Expanded(
                  child: Row(
                    // Without stretch the strip shrink-wraps its content and
                    // floats vertically centred, leaving the scaffold showing
                    // above it.
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ToolbarStrip(),
                      Expanded(child: CanvasView()),
                      LayerPanel(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
