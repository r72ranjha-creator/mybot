import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// One SQLite file for everything MyBot remembers. Kept deliberately flat so
/// the Logs and Chat screens can query it without a big ORM.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'mybot.db');
    return openDatabase(
      path,
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE chat_messages (
            id TEXT PRIMARY KEY,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            plan_id TEXT,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE plans (
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
          CREATE TABLE strategies (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            symbol TEXT NOT NULL,
            timeframe TEXT NOT NULL,
            rules TEXT NOT NULL,
            active INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await db.execute('''
          CREATE TABLE signals (
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
          CREATE TABLE watchlist (
            id TEXT PRIMARY KEY,
            symbol TEXT NOT NULL,
            timeframe TEXT NOT NULL,
            strategy_id TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE approvals (
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
          CREATE TABLE activity_logs (
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
          CREATE TABLE app_rules (
            package TEXT PRIMARY KEY,
            label TEXT,
            blocked INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE usage (
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
          'CREATE INDEX idx_chat_created ON chat_messages(created_at)',
        );
        await db.execute(
          'CREATE INDEX idx_logs_created ON activity_logs(created_at)',
        );
        await db.execute(
          'CREATE INDEX idx_signals_created ON signals(created_at)',
        );
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
