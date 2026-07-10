import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/state/file_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How many paths File → Open Recent remembers.
const int kMaxRecentFiles = 8;

/// The key the list is persisted under.
const String kRecentFilesKey = 'recentFiles';

/// The most recently opened or saved files, newest first.
///
/// Paths that no longer exist are pruned on load rather than shown and then
/// failing when clicked — a menu that lists a deleted file is worse than one
/// that has forgotten it.
class RecentFiles extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(kRecentFilesKey) ?? const [];
    final files = ref.read(fileServiceProvider);

    final kept = <String>[];
    for (final path in stored) {
      if (await files.exists(path)) kept.add(path);
    }
    if (kept.length != stored.length) await _persist(kept);
    return kept;
  }

  /// Puts [path] at the front, dropping any older mention of it.
  ///
  /// Awaits [future] rather than reading `state.value`: on the first call the
  /// initial load is still in flight, and writing state under it would be
  /// undone the moment the load finished.
  Future<void> add(String path) async {
    final current = await future;
    final next = [
      path,
      ...current.where((p) => p != path),
    ].take(kMaxRecentFiles).toList();
    state = AsyncData(next);
    await _persist(next);
  }

  /// Forgets [path] — used when opening it fails.
  Future<void> remove(String path) async {
    final current = await future;
    final next = current.where((p) => p != path).toList();
    state = AsyncData(next);
    await _persist(next);
  }

  Future<void> _persist(List<String> paths) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(kRecentFilesKey, paths);
  }
}

final recentFilesProvider = AsyncNotifierProvider<RecentFiles, List<String>>(
  RecentFiles.new,
);
