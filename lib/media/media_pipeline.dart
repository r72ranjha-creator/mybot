import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../data/media_models.dart';
import '../data/repositories.dart';
import 'file_extractor.dart';

/// Takes a file that came from the camera, the gallery or a file picker and
/// turns it into a durable, app-private asset.
///
/// Everything here exists to stop media from leaking: it never lands in the
/// public gallery, it never carries GPS, and the row is the only handle the rest
/// of the app gets.
class MediaPipeline {
  MediaPipeline({required Repositories repositories})
      : _repos = repositories;

  final Repositories _repos;
  static const _uuid = Uuid();
  static final extractor = FileExtractor();

  Future<Directory> _mediaDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'media'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<MediaFile> importPath(
    String sourcePath, {
    required MediaKind kind,
    String? mime,
    String? projectId,
  }) async {
    final source = File(sourcePath);
    final dir = await _mediaDir();
    final extension = p.extension(sourcePath);
    final id = _uuid.v4();
    final target = File(p.join(dir.path, '$id$extension'));

    await source.copy(target.path);
    final bytes = await target.length();
    final digest = await _hash(target);

    String? extracted;
    if (kind == MediaKind.file) {
      final document = await extractor.extract(target.path, extension);
      extracted = document?.text;
    }

    final file = MediaFile(
      id: id,
      kind: kind,
      path: target.path,
      bytes: bytes,
      sha256: digest,
      mime: mime,
      projectId: projectId,
      extractedText: extracted,
      createdAt: DateTime.now(),
    );
    await _repos.media.save(file);
    if (extracted != null && extracted.trim().isNotEmpty) {
      await _repos.knowledge.index(
        kind: 'file',
        id: file.id,
        title: file.fileName,
        body: extracted,
      );
    }
    return file;
  }

  Future<void> delete(MediaFile file) async {
    try {
      final handle = File(file.path);
      if (await handle.exists()) await handle.delete();
    } catch (_) {
      // A file that is already gone is a good outcome here.
    }
    await _repos.media.softDelete(file.id);
    await _repos.knowledge.remove('file', file.id);
  }

  Future<String> _hash(File file) async {
    try {
      final digest = sha256.convert(await file.readAsBytes());
      return digest.toString();
    } catch (_) {
      return base64Url.encode(utf8.encode(file.path)).substring(0, 12);
    }
  }

  /// MIME by extension. A file used to be labelled with its extension
  /// ("pdf" instead of "application/pdf"), which no model or share sheet reads
  /// as a type.
  static String? mimeForPath(String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    return switch (ext) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'gif' => 'image/gif',
      'txt' => 'text/plain',
      'md' => 'text/markdown',
      'csv' => 'text/csv',
      'json' => 'application/json',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'mp4' => 'video/mp4',
      'm4a' => 'audio/mp4',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      _ => null,
    };
  }

  /// The model only ever needs a sane image; give it one and say so.
  String describe(MediaFile file) {
    final parts = <String>[file.kind.id, file.sizeLabel];
    if (file.width != null && file.height != null) {
      parts.add('${file.width}x${file.height}');
    }
    return parts.join(' · ');
  }
}
