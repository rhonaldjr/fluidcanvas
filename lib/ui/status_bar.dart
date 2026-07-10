import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/state/state.dart';

/// Height of the status bar, in screen pixels.
const double kStatusBarHeight = 26;

/// Bottom strip: canvas size, on-screen scale, and the fit-to-window toggle.
class StatusBar extends ConsumerWidget {
  const StatusBar({required this.scale, super.key});

  /// Page screen size divided by document size. Task 14.1 replaces this with
  /// the session's zoom.
  final double scale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(activeSessionProvider);
    final document = session.document;

    return Container(
      key: const Key('status-bar'),
      height: kStatusBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Text(
            key: const Key('status-canvas-size'),
            '${document.canvasWidth} × ${document.canvasHeight}',
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(width: 16),
          Text(
            key: const Key('status-scale'),
            '${(scale * 100).round()}%',
            style: theme.textTheme.labelSmall,
          ),
          const Spacer(),
          Text('Fit to window', style: theme.textTheme.labelSmall),
          const SizedBox(width: 4),
          SizedBox(
            height: kStatusBarHeight,
            child: Switch(
              key: const Key('fit-to-window'),
              value: session.fitToWindow,
              onChanged: (value) =>
                  ref.read(sessionsProvider.notifier).setFitToWindow(value),
            ),
          ),
        ],
      ),
    );
  }
}
