import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/format/document_json.dart';
import 'package:inkpad/format/element_codec.dart';
import 'package:inkpad/format/manifest.dart';

/// Builds the bytes of a `.skd` archive.
///
/// `mimetype` is written first and **stored, not compressed**, so the file can
/// be sniffed by reading a fixed offset — the ODF/EPUB convention.
Uint8List encodeSkd(
  SkdDocument document, {
  required SkdManifest manifest,
  Uint8List? thumbnailPng,
}) {
  final archive = Archive();

  final mimetype = ArchiveFile.string('mimetype', kSkdMimeType)
    ..compression = CompressionType.none;
  archive.addFile(mimetype);

  archive
    ..addFile(_jsonFile('manifest.json', manifest.toJson()))
    ..addFile(_jsonFile('document.json', documentToJson(document)));

  for (final layer in document.layers) {
    final bytes = encodeElements(layer.elements);
    archive.addFile(ArchiveFile(elementFileFor(layer.id), bytes.length, bytes));
  }

  if (thumbnailPng != null) {
    archive.addFile(ArchiveFile.bytes('thumbnail.png', thumbnailPng));
  }

  return ZipEncoder().encodeBytes(archive);
}

/// Writes [document] to [path].
///
/// Atomic: the bytes go to a sibling temp file and are renamed into place, so a
/// crash mid-write cannot leave a half-written `.skd` where the old one was.
/// Rename within a directory is atomic on every platform we ship.
Future<void> writeSkdFile(
  String path,
  SkdDocument document, {
  required SkdManifest manifest,
  Uint8List? thumbnailPng,
}) async {
  final bytes = encodeSkd(
    document,
    manifest: manifest,
    thumbnailPng: thumbnailPng,
  );

  final temp = File('$path.tmp');
  try {
    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(path);
  } catch (_) {
    if (temp.existsSync()) await temp.delete();
    rethrow;
  }
}

ArchiveFile _jsonFile(String name, Map<String, dynamic> json) =>
    ArchiveFile.bytes(
      name,
      utf8.encode(const JsonEncoder.withIndent('  ').convert(json)),
    );
