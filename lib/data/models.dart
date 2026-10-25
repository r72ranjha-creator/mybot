import 'dart:convert';

import '../core/constants.dart';

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.planId,
  });

  final String id;

  /// user | assistant | system
  final String role;
  final String content;
  final DateTime createdAt;
  final String? planId;

  bool get isUser => role == 'user';

  Map<String, Object?> toMap() => {
        'id': id,
        'role': role,
        'content': content,
        'created_at': createdAt.millisecondsSinceEpoch,
        'plan_id': planId,
      };

  factory ChatMessage.fromMap(Map<String, Object?> map) => ChatMessage(
        id: map['id'] as String,
        role: map['role'] as String,
        content: map['content'] as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        planId: map['plan_id'] as String?,
      );
}

enum RiskLevel { readOnly, reversible, sensitive, irreversible }

extension RiskLevelX on RiskLevel {
  String get id => name;

  /// A step needs a human tap before it runs.
  bool needsApproval(SafetyLevel safety) => switch (safety) {
        SafetyLevel.strict => this != RiskLevel.readOnly,
        SafetyLevel.balanced =>
          this == RiskLevel.sensitive || this == RiskLevel.irreversible,
        SafetyLevel.permissive => this == RiskLevel.irreversible,
      };

  static RiskLevel parse(String? value) => RiskLevel.values.firstWhere(
        (r) => r.name == value,
        orElse: () => RiskLevel.sensitive,
      );
}

enum StepStatus { pending, running, done, failed, blocked, skipped }

class PlanStep {
  PlanStep({
    required this.index,
    required this.bot,
    required this.action,
    this.target = '',
    this.params = const {},
    this.risk = RiskLevel.sensitive,
    this.status = StepStatus.pending,
    this.result = '',
  });

  final int index;
  final String bot;
  final String action;
  final String target;
  final Map<String, Object?> params;
  final RiskLevel risk;
  StepStatus status;
  String result;

  Map<String, Object?> toJson() => {
        'index': index,
        'bot': bot,
        'action': action,
        'target': target,
        'params': params,
        'risk': risk.id,
      };

  factory PlanStep.fromJson(Map<String, Object?> json) => PlanStep(
        index: (json['index'] as num?)?.toInt() ?? 0,
        bot: (json['bot'] as String?) ?? BotRole.manager,
        action: (json['action'] as String?) ?? 'answer',
        target: (json['target'] as String?) ?? '',
        params: (json['params'] as Map?)?.cast<String, Object?>() ?? const {},
        risk: RiskLevelX.parse(json['risk'] as String?),
      );
}

class TaskPlan {
  TaskPlan({
    required this.id,
    required this.intent,
    required this.language,
    required this.steps,
    required this.createdAt,
    this.summary = '',
    this.status = 'planned',
  });

  final String id;
  final String intent;
  final String language;
  final List<PlanStep> steps;
  final DateTime createdAt;
  String summary;
  String status;

  bool get hasBlockedStep => steps.any((s) => s.status == StepStatus.blocked);

  Map<String, Object?> toMap() => {
        'id': id,
        'intent': intent,
        'language': language,
        'summary': summary,
        'status': status,
        'steps': jsonEncode(steps.map((s) => s.toJson()).toList()),
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory TaskPlan.fromMap(Map<String, Object?> map) {
    final raw = (map['steps'] as String?) ?? '[]';
    final list = (jsonDecode(raw) as List).cast<Map<String, Object?>>();
    return TaskPlan(
      id: map['id'] as String,
      intent: (map['intent'] as String?) ?? '',
      language: (map['language'] as String?) ?? 'en',
      summary: (map['summary'] as String?) ?? '',
      status: (map['status'] as String?) ?? 'planned',
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      steps: list.map(PlanStep.fromJson).toList(),
    );
  }
}

class Strategy {
  Strategy({
    required this.id,
    required this.name,
    required this.symbol,
    required this.timeframe,
    required this.rules,
    this.active = true,
  });

  final String id;
  final String name;
  final String symbol;
  final String timeframe;

  /// Structured, human-authored rules. This map is the single source of truth
  /// the vision model must judge the chart against.
  final Map<String, Object?> rules;
  final bool active;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'symbol': symbol,
        'timeframe': timeframe,
        'rules': jsonEncode(rules),
        'active': active ? 1 : 0,
      };

  factory Strategy.fromMap(Map<String, Object?> map) => Strategy(
        id: map['id'] as String,
        name: map['name'] as String,
        symbol: map['symbol'] as String,
        timeframe: map['timeframe'] as String,
        rules: ((jsonDecode((map['rules'] as String?) ?? '{}')) as Map)
            .cast<String, Object?>(),
        active: (map['active'] as int? ?? 1) == 1,
      );
}

class TradeSignal {
  TradeSignal({
    required this.id,
    required this.symbol,
    required this.timeframe,
    required this.direction,
    required this.entryLow,
    required this.entryHigh,
    required this.stopLoss,
    required this.takeProfit,
    required this.confidence,
    required this.reason,
    required this.createdAt,
    this.strategyId,
    this.status = 'new',
    this.screenshotPath,
  });

  final String id;
  final String symbol;
  final String timeframe;

  /// long | short | no_trade
  final String direction;
  final double entryLow;
  final double entryHigh;
  final double stopLoss;
  final double takeProfit;
  final int confidence;
  final String reason;
  final DateTime createdAt;
  final String? strategyId;
  String status;
  String? screenshotPath;

  Map<String, Object?> toMap() => {
        'id': id,
        'symbol': symbol,
        'timeframe': timeframe,
        'direction': direction,
        'entry_low': entryLow,
        'entry_high': entryHigh,
        'stop_loss': stopLoss,
        'take_profit': takeProfit,
        'confidence': confidence,
        'reason': reason,
        'strategy_id': strategyId,
        'status': status,
        'screenshot_path': screenshotPath,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory TradeSignal.fromMap(Map<String, Object?> map) => TradeSignal(
        id: map['id'] as String,
        symbol: map['symbol'] as String,
        timeframe: (map['timeframe'] as String?) ?? '',
        direction: map['direction'] as String,
        entryLow: (map['entry_low'] as num).toDouble(),
        entryHigh: (map['entry_high'] as num).toDouble(),
        stopLoss: (map['stop_loss'] as num).toDouble(),
        takeProfit: (map['take_profit'] as num).toDouble(),
        confidence: (map['confidence'] as num).toInt(),
        reason: (map['reason'] as String?) ?? '',
        strategyId: map['strategy_id'] as String?,
        status: (map['status'] as String?) ?? 'new',
        screenshotPath: map['screenshot_path'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );
}

class WatchlistEntry {
  WatchlistEntry({
    required this.id,
    required this.symbol,
    required this.timeframe,
    this.strategyId,
  });

  final String id;
  final String symbol;
  final String timeframe;
  final String? strategyId;

  Map<String, Object?> toMap() => {
        'id': id,
        'symbol': symbol,
        'timeframe': timeframe,
        'strategy_id': strategyId,
      };

  factory WatchlistEntry.fromMap(Map<String, Object?> map) => WatchlistEntry(
        id: map['id'] as String,
        symbol: map['symbol'] as String,
        timeframe: (map['timeframe'] as String?) ?? '15m',
        strategyId: map['strategy_id'] as String?,
      );
}

class ApprovalRequest {
  ApprovalRequest({
    required this.id,
    required this.kind,
    required this.title,
    required this.detail,
    required this.payload,
    required this.createdAt,
    this.screenshotPath,
    this.status = 'pending',
  });

  final String id;

  /// step | trade | send | purchase
  final String kind;
  final String title;
  final String detail;
  final Map<String, Object?> payload;
  final String? screenshotPath;
  final DateTime createdAt;
  String status;

  Map<String, Object?> toMap() => {
        'id': id,
        'kind': kind,
        'title': title,
        'detail': detail,
        'payload': jsonEncode(payload),
        'screenshot_path': screenshotPath,
        'status': status,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory ApprovalRequest.fromMap(Map<String, Object?> map) => ApprovalRequest(
        id: map['id'] as String,
        kind: map['kind'] as String,
        title: map['title'] as String,
        detail: (map['detail'] as String?) ?? '',
        payload: ((jsonDecode((map['payload'] as String?) ?? '{}')) as Map)
            .cast<String, Object?>(),
        screenshotPath: map['screenshot_path'] as String?,
        status: (map['status'] as String?) ?? 'pending',
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );
}

class ActivityLog {
  ActivityLog({
    required this.id,
    required this.app,
    required this.action,
    required this.model,
    required this.status,
    required this.createdAt,
    this.screenshotPath,
    this.detail = '',
  });

  final String id;
  final String app;
  final String action;
  final String model;
  final String status;
  final DateTime createdAt;
  final String? screenshotPath;
  final String detail;

  Map<String, Object?> toMap() => {
        'id': id,
        'app': app,
        'action': action,
        'model': model,
        'status': status,
        'screenshot_path': screenshotPath,
        'detail': detail,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory ActivityLog.fromMap(Map<String, Object?> map) => ActivityLog(
        id: map['id'] as String,
        app: (map['app'] as String?) ?? '',
        action: (map['action'] as String?) ?? '',
        model: (map['model'] as String?) ?? '',
        status: (map['status'] as String?) ?? '',
        screenshotPath: map['screenshot_path'] as String?,
        detail: (map['detail'] as String?) ?? '',
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );
}

class AppRule {
  AppRule({
    required this.package,
    required this.label,
    this.blocked = false,
  });

  final String package;
  final String label;
  final bool blocked;

  Map<String, Object?> toMap() => {
        'package': package,
        'label': label,
        'blocked': blocked ? 1 : 0,
      };

  factory AppRule.fromMap(Map<String, Object?> map) => AppRule(
        package: map['package'] as String,
        label: (map['label'] as String?) ?? '',
        blocked: (map['blocked'] as int? ?? 0) == 1,
      );
}

class UsageEntry {
  UsageEntry({
    required this.id,
    required this.role,
    required this.provider,
    required this.model,
    required this.inputTokens,
    required this.outputTokens,
    required this.createdAt,
  });

  final String id;
  final String role;
  final String provider;
  final String model;
  final int inputTokens;
  final int outputTokens;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'role': role,
        'provider': provider,
        'model': model,
        'input_tokens': inputTokens,
        'output_tokens': outputTokens,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory UsageEntry.fromMap(Map<String, Object?> map) => UsageEntry(
        id: map['id'] as String,
        role: (map['role'] as String?) ?? '',
        provider: (map['provider'] as String?) ?? '',
        model: (map['model'] as String?) ?? '',
        inputTokens: (map['input_tokens'] as int?) ?? 0,
        outputTokens: (map['output_tokens'] as int?) ?? 0,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );
}

/// A provider the user has configured, plus the API key reference.
class ProviderConfig {
  ProviderConfig({
    required this.id,
    required this.kind,
    required this.label,
    required this.baseUrl,
    this.enabled = true,
  });

  final String id;
  final ProviderKind kind;
  final String label;
  final String baseUrl;
  final bool enabled;

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'label': label,
        'baseUrl': baseUrl,
        'enabled': enabled,
      };

  factory ProviderConfig.fromJson(Map<String, Object?> json) => ProviderConfig(
        id: json['id'] as String,
        kind: ProviderKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => ProviderKind.openai,
        ),
        label: (json['label'] as String?) ?? '',
        baseUrl: (json['baseUrl'] as String?) ?? '',
        enabled: (json['enabled'] as bool?) ?? true,
      );

  ProviderConfig copyWith({String? baseUrl, bool? enabled}) => ProviderConfig(
        id: id,
        kind: kind,
        label: label,
        baseUrl: baseUrl ?? this.baseUrl,
        enabled: enabled ?? this.enabled,
      );
}

/// Which model a role uses, and what to fall back to.
class RoleConfig {
  RoleConfig({
    required this.role,
    required this.providerId,
    required this.model,
    List<ModelRef> fallbacks = const [],
    this.enabled = true,
  }) : fallbacks = List<ModelRef>.unmodifiable(fallbacks);

  final String role;
  final String providerId;
  final String model;
  final List<ModelRef> fallbacks;
  final bool enabled;

  Map<String, Object?> toJson() => {
        'role': role,
        'providerId': providerId,
        'model': model,
        'fallbacks': fallbacks
            .map((f) => {'providerId': f.providerId, 'model': f.model})
            .toList(),
        'enabled': enabled,
      };

  factory RoleConfig.fromJson(Map<String, Object?> json) => RoleConfig(
        role: json['role'] as String,
        providerId: (json['providerId'] as String?) ?? '',
        model: (json['model'] as String?) ?? '',
        fallbacks: ((json['fallbacks'] as List?) ?? const [])
            .map((e) => ModelRef.fromJson((e as Map).cast<String, Object?>()))
            .toList(),
        enabled: (json['enabled'] as bool?) ?? true,
      );

  RoleConfig copyWith({
    String? providerId,
    String? model,
    List<ModelRef>? fallbacks,
    bool? enabled,
  }) =>
      RoleConfig(
        role: role,
        providerId: providerId ?? this.providerId,
        model: model ?? this.model,
        fallbacks: fallbacks ?? this.fallbacks,
        enabled: enabled ?? this.enabled,
      );
}

class ModelRef {
  ModelRef({required this.providerId, required this.model});

  final String providerId;
  final String model;

  factory ModelRef.fromJson(Map<String, Object?> json) => ModelRef(
        providerId: (json['providerId'] as String?) ?? '',
        model: (json['model'] as String?) ?? '',
      );
}
