import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// Families offered when the platform cannot be enumerated.
///
/// A name here is only a *candidate*: it is shown to the user after
/// [isFontAvailable] has confirmed the system actually has it.
const List<String> kFallbackFontFamilies = [
  'DejaVu Sans',
  'DejaVu Serif',
  'DejaVu Sans Mono',
  'Liberation Sans',
  'Liberation Serif',
  'Liberation Mono',
  'Noto Sans',
  'Noto Serif',
  'Ubuntu',
  'Ubuntu Mono',
  'Cantarell',
  'FreeSans',
];

/// How many families the picker will show. Fontconfig on a full desktop can
/// report several hundred; a 76px strip cannot.
const int kMaxFontFamilies = 60;

/// A family name no system has. The yardstick for "this resolved to the
/// default", used by [isFontAvailable].
const String kMissingFamilyProbe = '__inkpad_no_such_family__';

/// Whether the system can actually render [family].
///
/// Flutter exposes no API to enumerate or query installed fonts, so this
/// *measures*: a family the engine cannot resolve silently falls back to the
/// default, and lays out identically to a family that certainly does not
/// exist. Different metrics therefore mean the font was found.
///
/// Two caveats, both deliberate:
///  * The empty family is the system default and is always available.
///  * A real font whose metrics coincide exactly with the default's would read
///    as missing. That costs the user a warning label, never their text.
bool isFontAvailable(String family) {
  if (family.isEmpty) return true;
  return _measure(family) != _measure(kMissingFamilyProbe);
}

/// Glyphs chosen to differ between typefaces: mixed widths, ascenders and
/// descenders.
const String _probeText = 'MWil1@gjq';

Size _measure(String family) {
  final painter = TextPainter(
    text: TextSpan(
      text: _probeText,
      style: TextStyle(fontFamily: family, fontSize: 48),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final size = painter.size;
  painter.dispose();
  return size;
}

/// The font families installed on this machine, sorted, at most
/// [kMaxFontFamilies] of them.
///
/// Asks fontconfig on Linux. Everywhere else — and whenever `fc-list` is
/// missing or fails — falls back to [kFallbackFontFamilies] filtered by
/// [isFontAvailable], so the picker never offers a font that will not render.
/// macOS enumeration arrives with its build, in Phase 16.
Future<List<String>> systemFontFamilies() async {
  final families = Platform.isLinux ? await _fontconfigFamilies() : null;
  final found = families ?? kFallbackFontFamilies.where(isFontAvailable);
  final sorted = found.toSet().toList()..sort();
  return sorted.take(kMaxFontFamilies).toList();
}

Future<List<String>?> _fontconfigFamilies() async {
  try {
    final result = await Process.run('fc-list', [
      ':',
      'family',
    ], stdoutEncoding: const SystemEncoding());
    if (result.exitCode != 0) return null;

    final names = <String>{};
    for (final line in const LineSplitter().convert('${result.stdout}')) {
      // fc-list prints a comma-separated alias list per font; the first name
      // is the one Flutter will match on.
      final first = line.split(',').first.trim();
      if (first.isNotEmpty) names.add(first);
    }
    return names.isEmpty ? null : names.toList();
  } on ProcessException {
    return null; // No fontconfig. Fall back.
  }
}
