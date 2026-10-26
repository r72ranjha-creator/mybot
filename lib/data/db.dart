import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// One SQLite file for everything MyBot remembers. Kept deliberately flat so
/// the Logs and Chat screens can query it without a big ORM.
///
/// Schema history:
///   v1 — chat, plans, strategies, signals, watchlist, approvals, logs,
///        app rules, settings, usage.
///   v2 — media, projects, research, notes, saved links, internal FTS index.
///        Additive only: no v1 table is dropped or rewritten.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const schemaVersion = 2;

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'mybot.db');
    return openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await _createV1(db);
        await _upgradeToV2(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _upgradeToV2(db);
        }
      },
    );
  }

  Future<void> _createV1(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages (
        id TEXT PRIMARY KEY,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        plan_id TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS plans (
        id TEXT PRIMARY KEY,
        intent TEXT NOT NULL,
        language TEXT NOT NULL,
        summary TEXT,
        status TEXT NOT NULL,
        steps TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS strategies (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        symbol TEXT NOT NULL,
        timeframe TEXT NOT NULL,
        rules TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS signals (
        id TEXT PRIMARY KEY,
        symbol TEXT NOT NULL,
        timeframe TEXT,
        direction TEXT NOT NULL,
        entry_low REAL NOT NULL,
        entry_high REAL NOT NULL,
        stop_loss REAL NOT NULL,
        take_profit REAL NOT NULL,
        confidence INTEGER NOT NULL,
        reason TEXT,
        strategy_id TEXT,
        status TEXT NOT NULL,
        screenshot_path TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS watchlist (
        id TEXT PRIMARY KEY,
        symbol TEXT NOT NULL,
        timeframe TEXT NOT NULL,
        strategy_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS approvals (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        detail TEXT,
        payload TEXT NOT NULL,
        screenshot_path TEXT,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS activity_logs (
        id TEXT PRIMARY KEY,
        app TEXT,
        action TEXT,
        model TEXT,
        status TEXT,
        detail TEXT,
        screenshot_path TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_rules (
        package TEXT PRIMARY KEY,
        label TEXT,
        blocked INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS usage (
        id TEXT PRIMARY KEY,
        role TEXT,
        provider TEXT,
        model TEXT,
        input_tokens INTEGER,
        output_tokens INTEGER,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_chat_created ON chat_messages(created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_logs_created ON activity_logs(created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_signals_created ON signals(created_at)',
    );
  }

  /// Everything added in v2. Safe to re-run: every statement is IF NOT EXISTS
  /// and the two column additions check first.
  Future<void> _upgradeToV2(Database db) async {
    await _addColumnIfMissing(db, 'chat_messages', 'project_id', 'TEXT');
    await _addColumnIfMissing(db, 'chat_messages', 'attachment_count',
        'INTEGER NOT NULL DEFAULT 0');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS media_files (
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        path TEXT NOT NULL,
        mime TEXT,
        bytes INTEGER NOT NULL DEFAULT 0,
        width INTEGER,
        height INTEGER,
        duration_ms INTEGER,
        sha256 TEXT,
        project_id TEXT,
        extracted_text TEXT,
        created_at INTEGER NOT NULL,
        deleted_at INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_attachments (
        message_id TEXT NOT NULL,
        media_id TEXT NOT NULL,
        position INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (message_id, media_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        instructions TEXT,
        icon TEXT,
        search_prefs TEXT,
        archived INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS project_files (
        project_id TEXT NOT NULL,
        media_id TEXT,
        report_id TEXT,
        link_url TEXT,
        added_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS research_reports (
        id TEXT PRIMARY KEY,
        project_id TEXT,
        parent_id TEXT,
        question TEXT NOT NULL,
        mode TEXT NOT NULL,
        summary TEXT,
        body_md TEXT,
        conclusions TEXT,
        status TEXT NOT NULL DEFAULT 'draft',
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS research_queries (
        id TEXT PRIMARY KEY,
        report_id TEXT NOT NULL,
        query TEXT NOT NULL,
        provider TEXT,
        hits INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS research_sources (
        id TEXT PRIMARY KEY,
        report_id TEXT NOT NULL,
        url TEXT NOT NULL,
        title TEXT,
        domain TEXT,
        published_at INTEGER,
        snippet TEXT,
        trust TEXT,
        trust_reason TEXT,
        used_in_answer INTEGER NOT NULL DEFAULT 1,
        position INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS source_ratings (
        domain TEXT PRIMARY KEY,
        trust TEXT NOT NULL,
        notes TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS saved_links (
        id TEXT PRIMARY KEY,
        url TEXT NOT NULL,
        title TEXT,
        note TEXT,
        project_id TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scheduled_research (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        question TEXT NOT NULL,
        mode TEXT NOT NULL DEFAULT 'quick',
        cadence TEXT NOT NULL,
        time_of_day TEXT NOT NULL,
        timezone TEXT NOT NULL DEFAULT 'Asia/Karachi',
        project_id TEXT,
        enabled INTEGER NOT NULL DEFAULT 1,
        last_run_at INTEGER,
        next_run_at INTEGER,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS user_notes (
        id TEXT PRIMARY KEY,
        title TEXT,
        body TEXT NOT NULL,
        project_id TEXT,
        tags TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS internal_fts USING fts5(
        source_kind,
        source_id UNINDEXED,
        title,
        body,
        tokenize = 'unicode61'
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_media_created ON media_files(created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_reports_created ON research_reports(created_at)',
    );
  }

  Future<bool> _columnExists(Database db, String table, String column) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.any((row) => row['name'] == column);
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    if (await _columnExists(db, table, column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
