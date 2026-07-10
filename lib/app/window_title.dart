import 'package:flutter/services.dart';
import 'package:inkpad/state/document_session.dart';

/// The channel `linux/runner/my_application.cc` answers on.
///
/// Flutter has no Dart API for the desktop window's title, so the Linux runner
/// grows a `setTitle` handler. Other platforms have no host handler yet, and
/// [WindowTitle.set] treats that as a no-op rather than an error.
const MethodChannel kWindowChannel = MethodChannel('inkpad/window');

/// What the window is called while [session] is in front.
///
/// The asterisk is the same unsaved marker the tab's dot is, spelled for a
/// title bar that cannot draw one.
String windowTitleFor(DocumentSession session) =>
    '${session.isDirty ? '*' : ''}${session.title} — InkPad';

/// Sets the OS window title.
class WindowTitle {
  const WindowTitle([this.channel = kWindowChannel]);

  final MethodChannel channel;

  Future<void> set(String title) async {
    try {
      await channel.invokeMethod<void>('setTitle', title);
    } on MissingPluginException {
      // A platform whose runner has no handler — macOS until Phase 16, and
      // every widget test. The window keeps the title it was given at startup.
    }
  }
}
