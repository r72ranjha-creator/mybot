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

  factory AiConfig.fromJson(Map<String, Object?> json) {
    final base = AiConfig.defaults();
    final rawProviders = (json['providers'] as List?) ?? const [];
    final rawRoles = (json['roles'] as List?) ?? const [];
    if (rawProviders.isEmpty && rawRoles.isEmpty) return base;
    return AiConfig(
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
  });

  final bool onboarded;
  final String language;
  final bool darkMode;
  final bool notifications;
  final SafetyLevel safety;
  final bool stopRequested;
  final String? defaultStrategyId;

  AppSettings copyWith({
    bool? onboarded,
    String? language,
    bool? darkMode,
    bool? notifications,
    SafetyLevel? safety,
    bool? stopRequested,
    String? defaultStrategyId,
  }) =>
      AppSettings(
        onboarded: onboarded ?? this.onboarded,
        language: language ?? this.language,
        darkMode: darkMode ?? this.darkMode,
        notifications: notifications ?? this.notifications,
        safety: safety ?? this.safety,
        stopRequested: stopRequested ?? this.stopRequested,
        defaultStrategyId: defaultStrategyId ?? this.defaultStrategyId,
      );

  Map<String, Object?> toJson() => {
        'onboarded': onboarded,
        'language': language,
        'darkMode': darkMode,
        'notifications': notifications,
        'safety': safety.id,
        'defaultStrategyId': defaultStrategyId,
      };

  factory AppSettings.fromJson(Map<String, Object?> json) => AppSettings(
        onboarded: (json['onboarded'] as bool?) ?? false,
        language: (json['language'] as String?) ?? 'auto',
        darkMode: (json['darkMode'] as bool?) ?? true,
        notifications: (json['notifications'] as bool?) ?? true,
        safety: SafetyLevelX.parse(json['safety'] as String?),
        defaultStrategyId: json['defaultStrategyId'] as String?,
      );

  static const storageKey = 'app.settings';
}
