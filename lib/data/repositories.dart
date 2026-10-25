import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'db.dart';
import 'models.dart';

class ChatRepository {
  ChatRepository(this._db);
  final AppDatabase _db;

  Future<void> add(ChatMessage message) async {
    final db = await _db.database;
    await db.insert('chat_messages', message.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ChatMessage>> recent({int limit = 50}) async {
    final db = await _db.database;
    final rows = await db.query(
      'chat_messages',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(ChatMessage.fromMap).toList().reversed.toList();
  }

  Future<void> clear() async {
    final db = await _db.database;
    await db.delete('chat_messages');
  }
}

class PlanRepository {
  PlanRepository(this._db);
  final AppDatabase _db;

  Future<void> save(TaskPlan plan) async {
    final db = await _db.database;
    await db.insert('plans', plan.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<TaskPlan>> recent({int limit = 20}) async {
    final db = await _db.database;
    final rows = await db.query('plans', orderBy: 'created_at DESC', limit: limit);
    return rows.map(TaskPlan.fromMap).toList();
  }

  Future<TaskPlan?> byId(String id) async {
    final db = await _db.database;
    final rows =
        await db.query('plans', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return TaskPlan.fromMap(rows.first);
  }

  Future<TaskPlan?> active() async {
    final db = await _db.database;
    final rows = await db.query(
      'plans',
      where: 'status IN (?, ?, ?)',
      whereArgs: ['planned', 'running', 'awaiting_approval'],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return TaskPlan.fromMap(rows.first);
  }
}

class TradingRepository {
  TradingRepository(this._db);
  final AppDatabase _db;

  Future<void> saveStrategy(Strategy strategy) async {
    final db = await _db.database;
    await db.insert('strategies', strategy.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Strategy>> strategies() async {
    final db = await _db.database;
    final rows = await db.query('strategies', orderBy: 'name ASC');
    return rows.map(Strategy.fromMap).toList();
  }

  Future<void> deleteStrategy(String id) async {
    final db = await _db.database;
    await db.delete('strategies', where: 'id = ?', whereArgs: [id]);
  }

  Future<Strategy?> strategyById(String id) async {
    final db = await _db.database;
    final rows =
        await db.query('strategies', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Strategy.fromMap(rows.first);
  }

  Future<void> saveSignal(TradeSignal signal) async {
    final db = await _db.database;
    await db.insert('signals', signal.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<TradeSignal>> signals({int limit = 50}) async {
    final db = await _db.database;
    final rows =
        await db.query('signals', orderBy: 'created_at DESC', limit: limit);
    return rows.map(TradeSignal.fromMap).toList();
  }

  Future<void> updateSignalStatus(String id, String status) async {
    final db = await _db.database;
    await db.update('signals', {'status': status},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<List<WatchlistEntry>> watchlist() async {
    final db = await _db.database;
    final rows = await db.query('watchlist', orderBy: 'symbol ASC');
    return rows.map(WatchlistEntry.fromMap).toList();
  }

  Future<void> saveWatch(WatchlistEntry entry) async {
    final db = await _db.database;
    await db.insert('watchlist', entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeWatch(String id) async {
    final db = await _db.database;
    await db.delete('watchlist', where: 'id = ?', whereArgs: [id]);
  }
}

class ApprovalRepository {
  ApprovalRepository(this._db);
  final AppDatabase _db;

  Future<void> create(ApprovalRequest request) async {
    final db = await _db.database;
    await db.insert('approvals', request.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ApprovalRequest>> pending() async {
    final db = await _db.database;
    final rows = await db.query(
      'approvals',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'created_at DESC',
    );
    return rows.map(ApprovalRequest.fromMap).toList();
  }

  Future<List<ApprovalRequest>> recent({int limit = 40}) async {
    final db = await _db.database;
    final rows =
        await db.query('approvals', orderBy: 'created_at DESC', limit: limit);
    return rows.map(ApprovalRequest.fromMap).toList();
  }

  Future<void> resolve(String id, String status) async {
    final db = await _db.database;
    await db.update('approvals', {'status': status},
        where: 'id = ?', whereArgs: [id]);
  }
}

class LogRepository {
  LogRepository(this._db);
  final AppDatabase _db;

  Future<void> add(ActivityLog entry) async {
    final db = await _db.database;
    await db.insert('activity_logs', entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<ActivityLog>> recent({int limit = 200, String? app}) async {
    final db = await _db.database;
    final rows = await db.query(
      'activity_logs',
      where: app == null ? null : 'app = ?',
      whereArgs: app == null ? null : [app],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(ActivityLog.fromMap).toList();
  }

  Future<void> clear() async {
    final db = await _db.database;
    await db.delete('activity_logs');
  }
}

class AppRuleRepository {
  AppRuleRepository(this._db);
  final AppDatabase _db;

  Future<List<AppRule>> all() async {
    final db = await _db.database;
    final rows = await db.query('app_rules', orderBy: 'label ASC');
    return rows.map(AppRule.fromMap).toList();
  }

  Future<void> upsert(AppRule rule) async {
    final db = await _db.database;
    await db.insert('app_rules', rule.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> setBlocked(String package, bool blocked) async {
    final db = await _db.database;
    await db.update(
      'app_rules',
      {'blocked': blocked ? 1 : 0},
      where: 'package = ?',
      whereArgs: [package],
    );
  }

  Future<Set<String>> blockedPackages() async {
    final db = await _db.database;
    final rows = await db.query(
      'app_rules',
      columns: ['package'],
      where: 'blocked = 1',
    );
    return rows.map((r) => r['package'] as String).toSet();
  }
}

class SettingsRepository {
  SettingsRepository(this._db);
  final AppDatabase _db;

  Future<Map<String, String>> all() async {
    final db = await _db.database;
    final rows = await db.query('settings');
    return {
      for (final row in rows) row['key'] as String: (row['value'] as String?) ?? '',
    };
  }

  Future<void> put(String key, String value) async {
    final db = await _db.database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> get(String key) async {
    final db = await _db.database;
    final rows =
        await db.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }
}

class UsageRepository {
  UsageRepository(this._db);
  final AppDatabase _db;

  Future<void> add(UsageEntry entry) async {
    final db = await _db.database;
    await db.insert('usage', entry.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, int>> totals() async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS calls, '
      'COALESCE(SUM(input_tokens),0) AS tin, '
      'COALESCE(SUM(output_tokens),0) AS tout FROM usage',
    );
    final row = rows.first;
    return {
      'calls': (row['calls'] as num?)?.toInt() ?? 0,
      'input': (row['tin'] as num?)?.toInt() ?? 0,
      'output': (row['tout'] as num?)?.toInt() ?? 0,
    };
  }

  Future<List<Map<String, Object?>>> byRole() async {
    final db = await _db.database;
    return db.rawQuery(
      'SELECT role, COUNT(*) AS calls, '
      'COALESCE(SUM(input_tokens),0) + COALESCE(SUM(output_tokens),0) AS tokens '
      'FROM usage GROUP BY role ORDER BY tokens DESC',
    );
  }
}

/// Convenience bundle so a widget only needs one provider.
class Repositories {
  Repositories(AppDatabase db)
      : chat = ChatRepository(db),
        plans = PlanRepository(db),
        trading = TradingRepository(db),
        approvals = ApprovalRepository(db),
        logs = LogRepository(db),
        appRules = AppRuleRepository(db),
        settings = SettingsRepository(db),
        usage = UsageRepository(db);

  final ChatRepository chat;
  final PlanRepository plans;
  final TradingRepository trading;
  final ApprovalRepository approvals;
  final LogRepository logs;
  final AppRuleRepository appRules;
  final SettingsRepository settings;
  final UsageRepository usage;
}

String encodeJson(Object? value) => jsonEncode(value);
