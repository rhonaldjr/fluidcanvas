import 'package:flutter/services.dart';
import 'package:inkpad/state/document_session.dart';

/// The channel `linux/runner/my_application.cc` answers on.
///
/// Flutter has no Dart API for the desktop window's title or icon, so the
/// Linux runner grows `setTitle` and `setIcon` handlers. Other platforms have
/// no host handler yet, and [WindowTitle] treats that as a no-op, not an error.
const MethodChannel kWindowChannel = MethodChannel('inkpad/window');

/// The icon shipped in the bundle and handed to GTK at startup.
const String kWindowIconAsset =
    'packaging/linux/icons/hicolor/256x256/apps/inkpad.png';

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

  /// Hands GTK the window icon's pixels.
  ///
  /// Returns whether the host took it. The bytes are the PNG we ship, not an
  /// icon-theme name: inside an AppImage the theme cannot resolve one, and GTK
  /// warns and falls back to the stock icon.
  Future<bool> setIcon(Uint8List pngBytes) async {
    try {
      return await channel.invokeMethod<bool>('setIcon', pngBytes) ?? false;
    } on MissingPluginException {
      return false;
    }
  }
}
