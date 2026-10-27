import 'dart:convert';

import '../core/constants.dart';
import '../data/models.dart';

/// Everything about "which model answers what", persisted as one JSON blob in
/// the settings table so a backup is a single row.
class AiConfig {
  AiConfig({required this.providers, required this.roles});

  final List<ProviderConfig> providers;
  final List<RoleConfig> roles;

  static AiConfig defaults() {
    final providers = [
      for (final kind in ProviderKind.values)
        ProviderConfig(
          id: kind.name,
          kind: kind,
          label: kind.label,
          baseUrl: kind.defaultBaseUrl,
        ),
    ];
    final roles = [
      for (final role in BotRole.all)
        RoleConfig(
          role: role,
          providerId: role == BotRole.vision
              ? ProviderKind.gemini.name
              : ProviderKind.openai.name,
          model: role == BotRole.vision
              ? ProviderKind.gemini.defaultModel
              : ProviderKind.openai.defaultModel,
          fallbacks: role == BotRole.vision
              ? [
                  ModelRef(
                    providerId: ProviderKind.openai.name,
                    model: ProviderKind.openai.defaultModel,
                  ),
                ]
              : [
                  ModelRef(
                    providerId: ProviderKind.gemini.name,
                    model: ProviderKind.gemini.defaultModel,
                  ),
                  ModelRef(
                    providerId: ProviderKind.openrouter.name,
                    model: ProviderKind.openrouter.defaultModel,
                  ),
                ],
        ),
    ];
    return AiConfig(providers: providers, roles: roles);
  }

  ProviderConfig? provider(String id) {
    for (final provider in providers) {
      if (provider.id == id) return provider;
    }
    return null;
  }

  RoleConfig? role(String role) {
    for (final config in roles) {
      if (config.role == role) return config;
    }
    return null;
  }

  AiConfig withRole(RoleConfig updated) => AiConfig(
        providers: providers,
        roles: [
          for (final config in roles)
            if (config.role == updated.role) updated else config,
        ],
      );

  AiConfig withProvider(ProviderConfig updated) => AiConfig(
        providers: [
          for (final provider in providers)
            if (provider.id == updated.id) updated else provider,
        ],
        roles: roles,
      );

  Map<String, Object?> toJson() => {
        'providers': providers.map((p) => p.toJson()).toList(),
        'roles': roles.map((r) => r.toJson()).toList(),
      };

  /// A saved config from an older build will not know about roles added later.
  /// Merging defaults for the missing ones keeps every route mapped after an
  /// update instead of silently disabling a bot.
  AiConfig withMissingRoles() {
    final defaults = AiConfig.defaults();
    final missing = BotRole.all
        .where((role) => this.role(role) == null)
        .map((role) => defaults.role(role)!)
        .toList();
    if (missing.isEmpty) return this;
    return AiConfig(providers: providers, roles: [...roles, ...missing]);
  }

  factory AiConfig.fromJson(Map<String, Object?> json) {
    final base = AiConfig.defaults();
    final rawProviders = (json['providers'] as List?) ?? const [];
    final rawRoles = (json['roles'] as List?) ?? const [];
    if (rawProviders.isEmpty && rawRoles.isEmpty) return base;
    final merged = AiConfig(
      providers: rawProviders.isEmpty
          ? base.providers
          : rawProviders
              .map((e) => ProviderConfig.fromJson((e as Map).cast<String, Object?>()))
              .toList(),
      roles: rawRoles.isEmpty
          ? base.roles
          : rawRoles
              .map((e) => RoleConfig.fromJson((e as Map).cast<String, Object?>()))
              .toList(),
    );
    return merged.withMissingRoles();
  }

  String encode() => jsonEncode(toJson());

  static const storageKey = 'ai.config';

  static AiConfig decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return AiConfig.defaults();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return AiConfig.fromJson(decoded.cast<String, Object?>());
    } catch (_) {
      // A corrupt config must never brick the app: fall back to defaults.
    }
    return AiConfig.defaults();
  }
}

/// User-facing app settings (separate from AI routing).
class AppSettings {
  AppSettings({
    this.onboarded = false,
    this.language = 'auto',
    this.darkMode = true,
    this.notifications = true,
    this.safety = SafetyLevel.balanced,
    this.stopRequested = false,
    this.defaultStrategyId,
    this.allowOrderTap = false,
    this.voiceMuted = false,
    this.videoMaxSeconds = 60,
    this.lastProjectId,
  });

  final bool onboarded;
  final String language;
  final bool darkMode;
  final bool notifications;
  final SafetyLevel safety;
  final bool stopRequested;
  final String? defaultStrategyId;

  /// Off by default. When on, MyBot may press the order button — but only ever
  /// after an explicit per-press approval (see ManagerBot._tapTradeButton).
  final bool allowOrderTap;
  final bool voiceMuted;
  final int videoMaxSeconds;
  final String? lastProjectId;

  AppSettings copyWith({
    bool? onboarded,
    String? language,
    bool? darkMode,
    bool? notifications,
    SafetyLevel? safety,
    bool? stopRequested,
    String? defaultStrategyId,
    bool clearDefaultStrategy = false,
    bool? allowOrderTap,
    bool? voiceMuted,
    int? videoMaxSeconds,
    String? lastProjectId,
  }) =>
      AppSettings(
        onboarded: onboarded ?? this.onboarded,
        language: language ?? this.language,
        darkMode: darkMode ?? this.darkMode,
        notifications: notifications ?? this.notifications,
        safety: safety ?? this.safety,
        stopRequested: stopRequested ?? this.stopRequested,
        defaultStrategyId: clearDefaultStrategy
            ? null
            : (defaultStrategyId ?? this.defaultStrategyId),
        allowOrderTap: allowOrderTap ?? this.allowOrderTap,
        voiceMuted: voiceMuted ?? this.voiceMuted,
        videoMaxSeconds: videoMaxSeconds ?? this.videoMaxSeconds,
        lastProjectId: lastProjectId ?? this.lastProjectId,
      );

  // `stopRequested` is persisted on purpose: STOP is a safety state, and a
  // restart must not quietly hand the bot back to the user mid-halt.
  Map<String, Object?> toJson() => {
        'onboarded': onboarded,
        'language': language,
        'darkMode': darkMode,
        'notifications': notifications,
        'safety': safety.id,
        'stopRequested': stopRequested,
        'defaultStrategyId': defaultStrategyId,
        'allowOrderTap': allowOrderTap,
        'voiceMuted': voiceMuted,
        'videoMaxSeconds': videoMaxSeconds,
        'lastProjectId': lastProjectId,
      };

  factory AppSettings.fromJson(Map<String, Object?> json) => AppSettings(
        onboarded: (json['onboarded'] as bool?) ?? false,
        language: (json['language'] as String?) ?? 'auto',
        darkMode: (json['darkMode'] as bool?) ?? true,
        notifications: (json['notifications'] as bool?) ?? true,
        safety: SafetyLevelX.parse(json['safety'] as String?),
        stopRequested: (json['stopRequested'] as bool?) ?? false,
        defaultStrategyId: json['defaultStrategyId'] as String?,
        allowOrderTap: (json['allowOrderTap'] as bool?) ?? false,
        voiceMuted: (json['voiceMuted'] as bool?) ?? false,
        videoMaxSeconds: (json['videoMaxSeconds'] as int?) ?? 60,
        lastProjectId: json['lastProjectId'] as String?,
      );

  static const storageKey = 'app.settings';
}
