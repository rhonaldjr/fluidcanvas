import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/engine/system_fonts.dart';

/// The families the picker offers, once the platform has been asked.
///
/// Loading is asynchronous because it shells out to fontconfig; until it
/// resolves the picker shows only the current family.
final systemFontsProvider = FutureProvider<List<String>>(
  (ref) => systemFontFamilies(),
);

/// Answers "can this machine render that family?".
///
/// Behind a provider so a widget test can say yes or no without depending on
/// which fonts the machine running it happens to have — and because a test
/// binding resolves *every* family to the same test font, which would make the
/// real [isFontAvailable] answer "no" to all of them.
final fontAvailabilityProvider = Provider<bool Function(String)>(
  (ref) => isFontAvailable,
);
