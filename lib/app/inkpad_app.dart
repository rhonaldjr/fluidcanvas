import 'dart:ui' show AppExitResponse;

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
class InkPadApp extends ConsumerWidget {
  const InkPadApp({super.key, this.startupFiles = const []});

  final List<String> startupFiles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'InkPad',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.blueGrey),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.blueGrey,
        brightness: Brightness.dark,
      ),
      // The stored preference, or the system's until it has loaded.
      themeMode: ref.watch(themeModeProvider),
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

  /// Intercepts the OS's "close this window" request — the title-bar X, the
  /// dock/taskbar close, `wmctrl -c`, logout. Unlike `PopScope` (which only
  /// catches Navigator pops and never fires for a desktop window close), this
  /// is the seam the platform actually asks through before quitting.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    ref.read(autosaveTickerProvider).start();
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Riverpod's listen only fires on change, so name the first window.
      _title.set(windowTitleFor(ref.read(activeSessionProvider)));
      _setWindowIcon();
      _openStartupFiles();
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Reviews unsaved work before the window is allowed to close, and cancels
  /// the exit if the user backs out of any prompt.
  Future<AppExitResponse> _onExitRequested() async {
    if (!mounted) return AppExitResponse.exit;
    final proceed = await confirmQuit(context, ref);
    return proceed ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  /// Hands the shipped PNG to the host. A window with no icon is cosmetic, so
  /// a failure here is logged by the host and otherwise ignored.
  Future<void> _setWindowIcon() async {
    final data = await rootBundle.load(kWindowIconAsset);
    await _title.setIcon(data.buffer.asUint8List());
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

    // No `PopScope`: a desktop window close never arrives as a Navigator pop,
    // so it would never fire. The save review lives in [_onExitRequested]
    // (window close) and [attemptQuit] (File → Quit, Ctrl/Cmd+Q) instead.
    return const AppShell();
  }
}
