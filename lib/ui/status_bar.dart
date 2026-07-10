import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/state/state.dart';

/// Height of the status bar, in screen pixels.
const double kStatusBarHeight = 26;

/// Bottom strip: canvas size, on-screen scale, and the fit-to-window toggle.
class StatusBar extends ConsumerWidget {
  const StatusBar({required this.scale, super.key});

  /// Page screen size divided by document size, after the session's zoom.
  final double scale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(activeSessionProvider);
    final document = session.document;
    final snap = ref.watch(snapSettingsProvider);

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
          // Clicking the zoom puts the whole page back, as Ctrl+0 does.
          Tooltip(
            message: session.view.fitted
                ? 'Fit to viewport'
                : 'Reset zoom (Ctrl+0)',
            child: InkWell(
              key: const Key('status-scale'),
              onTap: () => ref.read(sessionsProvider.notifier).resetView(),
              child: Text(
                '${(scale * 100).round()}%',
                style: theme.textTheme.labelSmall,
              ),
            ),
          ),
          const SizedBox(width: 16),
          _Toggle(
            id: 'snap-elements',
            tooltip: 'Snap to elements (hold Alt to suspend)',
            icon: Icons.align_horizontal_left,
            on: snap.snapToElements,
            onPressed: () =>
                ref.read(snapSettingsProvider.notifier).toggleSnapToElements(),
          ),
          _Toggle(
            id: 'snap-grid',
            tooltip: 'Show and snap to the grid',
            icon: Icons.grid_4x4,
            on: snap.showGrid,
            onPressed: () =>
                ref.read(snapSettingsProvider.notifier).toggleGrid(),
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

/// A small on/off button in the status bar.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.id,
    required this.tooltip,
    required this.icon,
    required this.on,
    required this.onPressed,
  });

  final String id;
  final String tooltip;
  final IconData icon;
  final bool on;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    key: Key(id),
    tooltip: tooltip,
    isSelected: on,
    iconSize: 16,
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 26, height: 22),
    icon: Icon(icon),
    onPressed: onPressed,
  );
}
