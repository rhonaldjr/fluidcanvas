import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/file_actions.dart';

/// Height of the strip, and the width a tab shrinks to before the strip
/// starts scrolling instead.
const double kTabStripHeight = 34;
const double kTabMaxWidth = 200;
const double kTabMinWidth = 96;

/// One tab per open document, between the menu bar and the canvas.
///
/// Hidden when a single document is open: a lone tab is a title bar that
/// steals 34 pixels of canvas and tells the user nothing.
class TabStrip extends ConsumerWidget {
  const TabStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionsProvider);
    if (state.sessionCount < 2) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Container(
      key: const Key('tab-strip'),
      height: kTabStripHeight,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => _TabList(
                width: tabWidth(constraints.maxWidth, state.sessionCount),
              ),
            ),
          ),
          IconButton(
            key: const Key('tab-new'),
            iconSize: 18,
            tooltip: 'New tab',
            icon: const Icon(Icons.add),
            onPressed: () =>
                ref.read(sessionsProvider.notifier).openBlankSession(),
          ),
        ],
      ),
    );
  }
}

/// How wide each tab is, given the space and how many want it.
///
/// Tabs share the strip until they would be narrower than [kTabMinWidth];
/// past that they stop shrinking and the strip scrolls, because a 20px tab
/// shows no title at all.
double tabWidth(double available, int count) {
  if (count <= 0) return kTabMaxWidth;
  final share = available / count;
  return share.clamp(kTabMinWidth, kTabMaxWidth);
}

class _TabList extends ConsumerWidget {
  const _TabList({required this.width});

  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sessionsProvider);
    final sessions = ref.read(sessionsProvider.notifier);

    return ReorderableListView.builder(
      scrollDirection: Axis.horizontal,
      buildDefaultDragHandles: false,
      itemCount: state.sessionCount,
      onReorderItem: sessions.moveSession,
      itemBuilder: (context, index) {
        final session = state.sessions[index];
        return ReorderableDragStartListener(
          key: ValueKey(session.id),
          index: index,
          child: SizedBox(
            width: width,
            child: _Tab(
              title: session.title,
              dirty: session.isDirty,
              active: session.id == state.activeSessionId,
              onTap: () => sessions.setActiveSession(session.id),
              onClose: () => closeSessionInteractively(
                context,
                ref,
                sessionId: session.id,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.title,
    required this.dirty,
    required this.active,
    required this.onTap,
    required this.onClose,
  });

  final String title;
  final bool dirty;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Listener(
      // Middle-click closes, as it does in every browser and editor.
      onPointerDown: (event) {
        if (event.buttons == kMiddleMouseButton) onClose();
      },
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: active
                ? theme.colorScheme.surface
                : theme.colorScheme.surfaceContainerLow,
            border: Border(
              right: BorderSide(color: theme.dividerColor),
              bottom: BorderSide(
                width: 2,
                color: active ? theme.colorScheme.primary : Colors.transparent,
              ),
            ),
          ),
          padding: const EdgeInsets.only(left: 10),
          child: Row(
            children: [
              if (dirty)
                Padding(
                  key: const Key('tab-dirty'),
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.circle,
                    size: 8,
                    color: theme.colorScheme.primary,
                  ),
                ),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              IconButton(
                iconSize: 14,
                visualDensity: VisualDensity.compact,
                tooltip: 'Close $title',
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
