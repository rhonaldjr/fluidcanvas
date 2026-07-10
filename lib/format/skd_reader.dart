import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:inkpad/domain/models/models.dart';
import 'package:inkpad/format/document_json.dart';
import 'package:inkpad/format/element_codec.dart';
import 'package:inkpad/format/manifest.dart';
import 'package:inkpad/format/skd_exception.dart';

/// A document read back out of a `.skd`, with the manifest that came with it.
typedef SkdFile = ({SkdDocument document, SkdManifest manifest});

/// Parses the bytes of a `.skd` archive.
///
/// Throws only [SkdFormatException]: a corrupt ZIP, a missing entry, a version
/// from the future and a truncated blob all arrive with a reason.
SkdFile decodeSkd(Uint8List bytes, {String Function()? idFor}) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    throw SkdFormatException('not a readable archive ($e)');
  }

  final mimetype = _entry(archive, 'mimetype');
  final declared = utf8.decode(mimetype, allowMalformed: true).trim();
  if (declared != kSkdMimeType) {
    throw SkdFormatException('not a .skd file (mimetype "$declared")');
  }

  // Version first: a file from the future must be refused before anything else
  // is interpreted under rules that may have changed.
  final manifest = SkdManifest.fromJson(_json(archive, 'manifest.json'));
  final documentJson = _json(archive, 'document.json');

  final document = documentFromJson(documentJson, (layerId) {
    final blob = _entry(archive, elementFileFor(layerId));
    return decodeElements(blob, idFor: idFor);
  });

  return (document: document, manifest: manifest);
}

/// Reads and parses the `.skd` at [path].
Future<SkdFile> readSkdFile(String path, {String Function()? idFor}) async {
  final file = File(path);
  if (!file.existsSync()) {
    throw SkdFormatException('no such file: $path');
  }
  return decodeSkd(await file.readAsBytes(), idFor: idFor);
}

Uint8List _entry(Archive archive, String name) {
  final file = archive.findFile(name);
  if (file == null) {
    throw SkdFormatException('the archive has no "$name"');
  }
  // `content` inflates on first access, so a corrupt deflate stream throws
  // here rather than in `decodeBytes` — as a `FormatException` from the
  // inflater, which is not this library's exception. A caller that catches
  // `SkdFormatException` around an Open would otherwise see it escape.
  try {
    return file.content;
  } on SkdFormatException {
    rethrow;
  } on Object catch (e) {
    throw SkdFormatException('"$name" is corrupt ($e)');
  }
}

Map<String, dynamic> _json(Archive archive, String name) {
  final text = utf8.decode(_entry(archive, name), allowMalformed: true);
  final Object? parsed;
  try {
    parsed = jsonDecode(text);
  } catch (e) {
    throw SkdFormatException('"$name" is not valid JSON ($e)');
  }
  if (parsed is! Map<String, dynamic>) {
    throw SkdFormatException('"$name" is not a JSON object');
  }
  return parsed;
}
