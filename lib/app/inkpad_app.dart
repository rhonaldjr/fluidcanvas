import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/app/window_title.dart';
import 'package:inkpad/state/state.dart';
import 'package:inkpad/ui/ui.dart';

/// Root widget: owns theming and hosts the app shell.
///
/// [startupFiles] are `.skd` paths from the command line, opened once the
/// first frame has a `BuildContext` to show an error dialog against.
class InkPadApp extends StatelessWidget {
  const InkPadApp({super.key, this.startupFiles = const []});

  final List<String> startupFiles;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InkPad',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.blueGrey),
      home: _Desktop(startupFiles: startupFiles),
    );
  }
}

/// The parts of the app that only make sense in a real window: the OS window
/// title, the autosave timer, the quit prompt, and files from `argv`.
///
/// Deliberately not inside [AppShell]: a widget test that pumps the shell would
/// otherwise leave a three-minute timer pending and fail on it.
class _Desktop extends ConsumerStatefulWidget {
  const _Desktop({required this.startupFiles});

  final List<String> startupFiles;

  @override
  ConsumerState<_Desktop> createState() => _DesktopState();
}

class _DesktopState extends ConsumerState<_Desktop> {
  static const _title = WindowTitle();

  @override
  void initState() {
    super.initState();
    ref.read(autosaveTickerProvider).start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Riverpod's listen only fires on change, so name the first window.
      _title.set(windowTitleFor(ref.read(activeSessionProvider)));
      _openStartupFiles();
    });
  }

  Future<void> _openStartupFiles() async {
    for (final path in widget.startupFiles) {
      if (!mounted) return;
      await openSessionFromPath(context, ref, path);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The title tracks the active tab and its dirty flag, so it changes on
    // every stroke of an unsaved document — hence a listen, not a rebuild.
    ref.listen(activeSessionProvider, (previous, next) {
      final was = previous == null ? null : windowTitleFor(previous);
      final now = windowTitleFor(next);
      if (was != now) _title.set(now);
    });

    return PopScope(
      // Quitting is refused until every dirty document has been reviewed.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirmQuit(context, ref)) {
          await SystemNavigator.pop();
        }
      },
      child: const AppShell(),
    );
  }
}
