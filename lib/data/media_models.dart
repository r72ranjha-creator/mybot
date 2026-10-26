import 'dart:io';

enum MediaKind { photo, video, screenshot, file, audio }

extension MediaKindX on MediaKind {
  String get id => name;

  static MediaKind parse(String? value) => MediaKind.values.firstWhere(
        (kind) => kind.name == value,
        orElse: () => MediaKind.photo,
      );

  bool get isImage => this == MediaKind.photo || this == MediaKind.screenshot;
}

/// One imported asset. The bytes live as a file in app-private storage; the row
/// carries only the metadata the rest of the app needs.
class MediaFile {
  MediaFile({
    required this.id,
    required this.kind,
    required this.path,
    required this.bytes,
    required this.createdAt,
    this.mime,
    this.width,
    this.height,
    this.durationMs,
    this.sha256,
    this.projectId,
    this.extractedText,
    this.deletedAt,
  });

  final String id;
  final MediaKind kind;
  final String path;
  final int bytes;
  final DateTime createdAt;
  final String? mime;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? sha256;
  final String? projectId;
  final String? extractedText;
  final DateTime? deletedAt;

  String get fileName => path.split(Platform.pathSeparator).last;

  String get sizeLabel {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  MediaFile copyWith({
    String? extractedText,
    String? projectId,
    DateTime? deletedAt,
  }) =>
      MediaFile(
        id: id,
        kind: kind,
        path: path,
        bytes: bytes,
        createdAt: createdAt,
        mime: mime,
        width: width,
        height: height,
        durationMs: durationMs,
        sha256: sha256,
        projectId: projectId ?? this.projectId,
        extractedText: extractedText ?? this.extractedText,
        deletedAt: deletedAt ?? this.deletedAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'kind': kind.id,
        'path': path,
        'mime': mime,
        'bytes': bytes,
        'width': width,
        'height': height,
        'duration_ms': durationMs,
        'sha256': sha256,
        'project_id': projectId,
        'extracted_text': extractedText,
        'created_at': createdAt.millisecondsSinceEpoch,
        'deleted_at': deletedAt?.millisecondsSinceEpoch,
      };

  factory MediaFile.fromMap(Map<String, Object?> map) => MediaFile(
        id: map['id'] as String,
        kind: MediaKindX.parse(map['kind'] as String?),
        path: map['path'] as String,
        mime: map['mime'] as String?,
        bytes: (map['bytes'] as int?) ?? 0,
        width: map['width'] as int?,
        height: map['height'] as int?,
        durationMs: map['duration_ms'] as int?,
        sha256: map['sha256'] as String?,
        projectId: map['project_id'] as String?,
        extractedText: map['extracted_text'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        deletedAt: map['deleted_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['deleted_at'] as int),
      );
}
