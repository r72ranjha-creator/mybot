import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'db.dart';
import 'media_models.dart';
import 'repositories.dart';
import 'research_models.dart';

class MediaRepository {
  MediaRepository(this._db);
  final AppDatabase _db;

  Future<void> save(MediaFile file) async {
    final db = await _db.database;
    await db.insert('media_files', file.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<MediaFile?> byId(String id) async {
    final db = await _db.database;
    final rows =
        await db.query('media_files', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return MediaFile.fromMap(rows.first);
  }

  Future<MediaFile?> byHash(String sha256) async {
    final db = await _db.database;
    final rows = await db.query(
      'media_files',
      where: 'sha256 = ? AND deleted_at IS NULL',
      whereArgs: [sha256],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MediaFile.fromMap(rows.first);
  }

  Future<List<MediaFile>> recent({int limit = 100, String? projectId}) async {
    final db = await _db.database;
    final rows = await db.query(
      'media_files',
      where: projectId == null
          ? 'deleted_at IS NULL'
          : 'deleted_at IS NULL AND project_id = ?',
      whereArgs: projectId == null ? null : [projectId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(MediaFile.fromMap).toList();
  }

  Future<void> attach(String messageId, String mediaId, int position) async {
    final db = await _db.database;
    await db.insert(
      'chat_attachments',
      {'message_id': messageId, 'media_id': mediaId, 'position': position},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<MediaFile>> forMessage(String messageId) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT m.* FROM media_files m JOIN chat_attachments a ON a.media_id = m.id '
      'WHERE a.message_id = ? ORDER BY a.position ASC',
      [messageId],
    );
    return rows.map(MediaFile.fromMap).toList();
  }

  Future<void> softDelete(String id) async {
    final db = await _db.database;
    await db.update(
      'media_files',
      {'deleted_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> totalBytes() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(bytes),0) AS b FROM media_files WHERE deleted_at IS NULL',
    );
    return (rows.first['b'] as num?)?.toInt() ?? 0;
  }

  Future<void> clearAll() async {
    final db = await _db.database;
    await db.delete('chat_attachments');
    await db.delete('media_files');
  }
}

class ProjectRepository {
  ProjectRepository(this._db);
  final AppDatabase _db;

  Future<void> save(Project project) async {
    final db = await _db.database;
    await db.insert('projects', project.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Project>> all({bool includeArchived = false}) async {
    final db = await _db.database;
    final rows = await db.query(
      'projects',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'created_at DESC',
    );
    return rows.map(Project.fromMap).toList();
  }

  Future<Project?> byId(String id) async {
    final db = await _db.database;
    final rows =
        await db.query('projects', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Project.fromMap(rows.first);
  }

  Future<void> delete(String id) async {
    final db = await _db.database;
    await db.delete('projects', where: 'id = ?', whereArgs: [id]);
    await db.delete('project_files', where: 'project_id = ?', whereArgs: [id]);
  }

  Future<void> link({
    required String projectId,
    String? mediaId,
    String? reportId,
    String? linkUrl,
  }) async {
    final db = await _db.database;
    await db.insert('project_files', {
      'project_id': projectId,
      'media_id': mediaId,
      'report_id': reportId,
      'link_url': linkUrl,
      'added_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<Map<String, int>> counts(String projectId) async {
    final db = await _db.database;
    Future<int> count(String sql) async {
      final rows = await db.rawQuery(sql, [projectId]);
      return (rows.first.values.first as num?)?.toInt() ?? 0;
    }

    return {
      'chats': await count(
          'SELECT COUNT(*) FROM chat_messages WHERE project_id = ?'),
      'reports': await count(
          'SELECT COUNT(*) FROM research_reports WHERE project_id = ?'),
      'files': await count(
          'SELECT COUNT(*) FROM media_files WHERE project_id = ? AND deleted_at IS NULL'),
    };
  }
}

class ResearchRepository {
  ResearchRepository(this._db);
  final AppDatabase _db;

  Future<void> saveReport(ResearchReport report) async {
    final db = await _db.database;
    await db.insert('research_reports', report.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveSources(List<ResearchSource> sources) async {
    if (sources.isEmpty) return;
    final db = await _db.database;
    final batch = db.batch();
    for (final source in sources) {
      batch.insert('research_sources', source.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> saveQuery({
    required String id,
    required String reportId,
    required String query,
    required String provider,
    required int hits,
  }) async {
    final db = await _db.database;
    await db.insert('research_queries', {
      'id': id,
      'report_id': reportId,
      'query': query,
      'provider': provider,
      'hits': hits,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<ResearchSource>> sourcesFor(String reportId) async {
    final db = await _db.database;
    final rows = await db.query(
      'research_sources',
      where: 'report_id = ?',
      whereArgs: [reportId],
      orderBy: 'position ASC',
    );
    return rows.map(ResearchSource.fromMap).toList();
  }

  Future<ResearchReport?> byId(String id) async {
    final db = await _db.database;
    final rows = await db.query('research_reports',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final sources = await sourcesFor(id);
    return ResearchReport.fromMap(rows.first, sources: sources);
  }

  Future<List<ResearchReport>> recent({int limit = 30, String? projectId}) async {
    final db = await _db.database;
    final rows = await db.query(
      'research_reports',
      where: projectId == null ? null : 'project_id = ?',
      whereArgs: projectId == null ? null : [projectId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map((row) => ResearchReport.fromMap(row)).toList();
  }

  Future<void> delete(String id) async {
    final db = await _db.database;
    await db.delete('research_sources', where: 'report_id = ?', whereArgs: [id]);
    await db.delete('research_queries', where: 'report_id = ?', whereArgs: [id]);
    await db.delete('research_reports', where: 'id = ?', whereArgs: [id]);
  }

  // --- saved links & notes -------------------------------------------------

  Future<void> saveLink(SavedLink link) async {
    final db = await _db.database;
    await db.insert('saved_links', link.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<SavedLink>> links({String? projectId}) async {
    final db = await _db.database;
    final rows = await db.query(
      'saved_links',
      where: projectId == null ? null : 'project_id = ?',
      whereArgs: projectId == null ? null : [projectId],
      orderBy: 'created_at DESC',
    );
    return rows.map(SavedLink.fromMap).toList();
  }

  Future<void> saveNote(UserNote note) async {
    final db = await _db.database;
    await db.insert('user_notes', note.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<UserNote>> notes({String? projectId}) async {
    final db = await _db.database;
    final rows = await db.query(
      'user_notes',
      where: projectId == null ? null : 'project_id = ?',
      whereArgs: projectId == null ? null : [projectId],
      orderBy: 'created_at DESC',
    );
    return rows.map(UserNote.fromMap).toList();
  }

  Future<void> setSourceRating(String domain, SourceTrust trust,
      {String notes = ''}) async {
    final db = await _db.database;
    await db.insert(
      'source_ratings',
      {
        'domain': domain,
        'trust': trust.id,
        'notes': notes,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, SourceTrust>> ratings() async {
    final db = await _db.database;
    final rows = await db.query('source_ratings');
    return {
      for (final row in rows)
        row['domain'] as String: SourceTrustX.parse(row['trust'] as String?),
    };
  }
}

class InternalHit {
  InternalHit({
    required this.kind,
    required this.id,
    required this.title,
    required this.snippet,
    required this.createdAt,
  });

  final String kind;
  final String id;
  final String title;
  final String snippet;
  final DateTime createdAt;
}

/// Full-text index over everything the user has produced, so "what did I write
/// about BTC last week" is answered from the phone instead of the web.
class KnowledgeRepository {
  KnowledgeRepository(this._db);
  final AppDatabase _db;

  Future<void> index({
    required String kind,
    required String id,
    required String title,
    required String body,
  }) async {
    if (body.trim().isEmpty) return;
    final db = await _db.database;
    await db.delete('internal_fts',
        where: 'source_kind = ? AND source_id = ?', whereArgs: [kind, id]);
    await db.insert('internal_fts', {
      'source_kind': kind,
      'source_id': id,
      'title': title,
      'body': body,
    });
  }

  Future<void> remove(String kind, String id) async {
    final db = await _db.database;
    await db.delete('internal_fts',
        where: 'source_kind = ? AND source_id = ?', whereArgs: [kind, id]);
  }

  Future<List<InternalHit>> search(String query, {int limit = 8}) async {
    final terms = _sanitise(query);
    if (terms.isEmpty) return const [];
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT source_kind, source_id, title, '
      "snippet(internal_fts, 3, '[', ']', '…', 14) AS snip "
      'FROM internal_fts WHERE internal_fts MATCH ? ORDER BY rank LIMIT ?',
      [terms, limit],
    );
    return rows
        .map((row) => InternalHit(
              kind: (row['source_kind'] as String?) ?? 'chat',
              id: (row['source_id'] as String?) ?? '',
              title: (row['title'] as String?) ?? '',
              snippet: (row['snip'] as String?) ?? '',
              createdAt: DateTime.now(),
            ))
        .toList();
  }

  /// FTS5 treats punctuation as syntax; keep words and add a prefix wildcard so
  /// "trad" still finds "trading".
  String _sanitise(String query) {
    final words = query
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{Nd}\s]', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.length >= 2)
        .take(8)
        .map((word) => '$word*')
        .toList();
    return words.join(' OR ');
  }

  /// Rebuild the index from existing rows. Runs in the background after an
  /// upgrade so the migration itself stays fast.
  Future<int> reindex(Repositories repos) async {
    var count = 0;
    for (final message in await repos.chat.recent(limit: 400)) {
      await index(
        kind: 'chat',
        id: message.id,
        title: message.role,
        body: message.content,
      );
      count++;
    }
    for (final report in await repos.research.recent(limit: 100)) {
      await index(
        kind: 'report',
        id: report.id,
        title: report.question,
        body: '${report.summary}\n${report.bodyMarkdown}',
      );
      count++;
    }
    for (final note in await repos.research.notes()) {
      await index(kind: 'note', id: note.id, title: note.title, body: note.body);
      count++;
    }
    for (final media in await repos.media.recent(limit: 200)) {
      final text = media.extractedText;
      if (text == null || text.isEmpty) continue;
      await index(
        kind: 'file',
        id: media.id,
        title: media.fileName,
        body: text,
      );
      count++;
    }
    return count;
  }

  static String describe(InternalHit hit) =>
      '${hit.kind}: ${hit.title} — ${hit.snippet}';
}

String encodeJsonMap(Map<String, Object?> value) => jsonEncode(value);
