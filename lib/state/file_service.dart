import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/engine/thumbnail.dart';
import 'package:inkpad/format/format.dart';

/// The app's version, written into every manifest.
const String kAppVersion = '0.1.0';

/// The extension, without the dot, and the picker's filter.
const String kSkdExtension = 'skd';

const XTypeGroup kSkdTypeGroup = XTypeGroup(
  label: 'InkPad drawing',
  extensions: [kSkdExtension],
);

/// Everything the app does that touches the disk or a native dialog.
///
/// One seam, so a widget test can drive Save and Open without a GTK file
/// chooser and without writing to the developer's home directory. Production
/// code never constructs the real one directly — it reads [fileServiceProvider].
abstract interface class FileService {
  /// Asks where to save, or `null` when the user cancels.
  Future<String?> pickSavePath({required String suggestedName});

  /// Asks what to open. Empty when the user cancels.
  Future<List<String>> pickOpenPaths();

  /// Writes [document] to [path], replacing whatever was there.
  Future<void> write(String path, SkdDocument document);

  /// Reads a `.skd`. Throws [SkdFormatException] on anything malformed.
  Future<SkdFile> read(String path);

  Future<bool> exists(String path);

  Future<void> delete(String path);

  /// When [path] was last written, or `null` when it does not exist.
  Future<DateTime?> modifiedAt(String path);
}

/// The real one: `file_selector` for dialogs, `format/` for the bytes.
class PlatformFileService implements FileService {
  const PlatformFileService();

  @override
  Future<String?> pickSavePath({required String suggestedName}) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [kSkdTypeGroup],
    );
    if (location == null) return null;
    // A user who types "sketch" means "sketch.skd".
    final path = location.path;
    return path.toLowerCase().endsWith('.$kSkdExtension')
        ? path
        : '$path.$kSkdExtension';
  }

  @override
  Future<List<String>> pickOpenPaths() async {
    final files = await openFiles(acceptedTypeGroups: const [kSkdTypeGroup]);
    return [for (final file in files) file.path];
  }

  @override
  Future<void> write(String path, SkdDocument document) async {
    final now = DateTime.now().toUtc();
    await writeSkdFile(
      path,
      document,
      manifest: SkdManifest(
        appVersion: kAppVersion,
        createdUtc: now,
        modifiedUtc: now,
      ),
      thumbnailPng: await renderThumbnailPng(document),
    );
  }

  @override
  Future<SkdFile> read(String path) => readSkdFile(path);

  @override
  Future<bool> exists(String path) => File(path).exists();

  @override
  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<DateTime?> modifiedAt(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    return file.lastModified();
  }
}

final fileServiceProvider = Provider<FileService>(
  (ref) => const PlatformFileService(),
);
