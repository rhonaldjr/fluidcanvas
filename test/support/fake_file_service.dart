import 'dart:typed_data';

import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/format/format.dart';
import 'package:inkpad/state/state.dart';

/// An in-memory [FileService]: no GTK dialog, no disk, no clock.
///
/// The pickers answer with whatever the test queued. Everything written can be
/// read back, so Save-then-Open round-trips through the real codec — which is
/// the part worth testing — without touching the developer's home directory.
class FakeFileService implements FileService {
  FakeFileService({this.savePath, List<String>? openPaths})
    : openPaths = openPaths ?? [];

  /// What the save picker returns. `null` means the user cancelled.
  String? savePath;

  /// What the open picker returns. Empty means the user cancelled.
  List<String> openPaths;

  /// What the PNG export picker returns. `null` means the user cancelled.
  String? exportPath;

  /// Written files, by path.
  final Map<String, Uint8List> files = {};

  /// Modification times, so `recoveryFor` can be tested without a real clock.
  final Map<String, DateTime> times = {};

  /// Paths the pickers were asked about, and the suggested names they got.
  final List<String> suggestedNames = [];
  int saveCalls = 0;
  int openCalls = 0;
  int exportCalls = 0;

  /// When set, [write] throws it — a full disk, a read-only volume.
  Object? writeError;

  /// Seeds [path] with a real `.skd` holding [document].
  void seed(String path, SkdDocument document, {DateTime? at}) {
    final now = DateTime.utc(2026, 1, 1);
    files[path] = encodeSkd(
      document,
      manifest: SkdManifest(
        appVersion: kAppVersion,
        createdUtc: now,
        modifiedUtc: now,
      ),
    );
    times[path] = at ?? now;
  }

  /// Seeds [path] with bytes that are not a `.skd` at all.
  void seedCorrupt(String path) {
    files[path] = Uint8List.fromList([1, 2, 3, 4]);
    times[path] = DateTime.utc(2026, 1, 1);
  }

  @override
  Future<String?> pickSavePath({required String suggestedName}) async {
    saveCalls++;
    suggestedNames.add(suggestedName);
    return savePath;
  }

  @override
  Future<List<String>> pickOpenPaths() async {
    openCalls++;
    return openPaths;
  }

  @override
  Future<String?> pickExportPath({required String suggestedName}) async {
    exportCalls++;
    suggestedNames.add(suggestedName);
    return exportPath;
  }

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async {
    if (writeError != null) throw writeError!;
    files[path] = bytes;
    times[path] = DateTime.utc(2026, 1, 1);
  }

  @override
  Future<void> write(String path, SkdDocument document) async {
    if (writeError != null) throw writeError!;
    final now = DateTime.utc(2026, 1, 1);
    files[path] = encodeSkd(
      document,
      manifest: SkdManifest(
        appVersion: kAppVersion,
        createdUtc: now,
        modifiedUtc: now,
      ),
    );
    times[path] = now;
  }

  @override
  Future<SkdFile> read(String path) async {
    final bytes = files[path];
    if (bytes == null) throw const SkdFormatException('no such file');
    return decodeSkd(bytes);
  }

  @override
  Future<bool> exists(String path) async => files.containsKey(path);

  @override
  Future<void> delete(String path) async {
    files.remove(path);
    times.remove(path);
  }

  @override
  Future<DateTime?> modifiedAt(String path) async => times[path];
}
