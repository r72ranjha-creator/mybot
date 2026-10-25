/// Stable identifiers used across DB rows, prompts and settings.
class BotRole {
  static const manager = 'manager';
  static const commandParser = 'command_parser';
  static const planner = 'planner';
  static const screenAgent = 'screen_agent';
  static const vision = 'vision';
  static const researcher = 'researcher';
  static const analyst = 'analyst';
  static const writer = 'writer';
  static const action = 'action';
  static const trading = 'trading_strategy';
  static const crypto = 'crypto_research';

  static const all = <String>[
    manager,
    commandParser,
    planner,
    screenAgent,
    vision,
    researcher,
    analyst,
    writer,
    action,
    trading,
    crypto,
  ];

  static const labels = <String, String>{
    manager: 'Manager',
    commandParser: 'Command parser',
    planner: 'Planner',
    screenAgent: 'Screen agent',
    vision: 'Vision analyst',
    researcher: 'Researcher',
    analyst: 'Analyst',
    writer: 'Writer',
    action: 'Action bot',
    trading: 'Trading strategy',
    crypto: 'Crypto research',
  };

  static const hints = <String, String>{
    manager: 'Routes a request, merges the answer',
    commandParser: 'Turns Urdu / English / Roman Urdu into a task',
    planner: 'Breaks a task into safe ordered steps',
    screenAgent: 'Reads and drives other apps',
    vision: 'Reads screenshots (chart analysis)',
    researcher: 'Gathers facts for a question',
    analyst: 'Compares, scores and decides',
    writer: 'Writes the final wording',
    action: 'Performs the approved action',
    trading: 'Applies your saved strategy rules',
    crypto: 'Token / market research',
  };
}

/// How much MyBot is allowed to do without asking.
enum SafetyLevel {
  /// Read-only work runs; anything that changes state asks first.
  strict,

  /// Reversible actions run; sending/spending/posting asks first.
  balanced,

  /// Only irreversible or money-moving steps ask.
  permissive,
}

extension SafetyLevelX on SafetyLevel {
  String get id => name;

  String get label => switch (this) {
        SafetyLevel.strict => 'Strict — ask before any change',
        SafetyLevel.balanced => 'Balanced — ask before anything that leaves a trace',
        SafetyLevel.permissive => 'Permissive — ask only for money or destruction',
      };

  static SafetyLevel parse(String? value) => SafetyLevel.values.firstWhere(
        (level) => level.name == value,
        orElse: () => SafetyLevel.balanced,
      );
}

/// Provider shapes MyBot can talk to. All four are HTTP APIs.
enum ProviderKind { openai, gemini, anthropic, openrouter }

extension ProviderKindX on ProviderKind {
  String get label => switch (this) {
        ProviderKind.openai => 'OpenAI',
        ProviderKind.gemini => 'Google Gemini',
        ProviderKind.anthropic => 'Anthropic',
        ProviderKind.openrouter => 'OpenRouter',
      };

  String get defaultBaseUrl => switch (this) {
        ProviderKind.openai => 'https://api.openai.com/v1',
        ProviderKind.gemini => 'https://generativelanguage.googleapis.com/v1beta',
        ProviderKind.anthropic => 'https://api.anthropic.com/v1',
        ProviderKind.openrouter => 'https://openrouter.ai/api/v1',
      };

  String get defaultModel => switch (this) {
        ProviderKind.openai => 'gpt-4o-mini',
        ProviderKind.gemini => 'gemini-2.0-flash',
        ProviderKind.anthropic => 'claude-3-5-sonnet-latest',
        ProviderKind.openrouter => 'openai/gpt-4o-mini',
      };

  /// Roles that need a vision-capable model.
  static const visionCapable = <String>{
    'gpt-4o-mini',
    'gpt-4o',
    'gpt-4.1-mini',
    'gemini-2.0-flash',
    'claude-3-5-sonnet-latest',
  };
}

class AppLimits {
  /// Hard ceilings so a runaway plan can never hammer the phone.
  static const maxStepsPerPlan = 12;
  static const maxRetriesPerStep = 2;
  static const maxScreenshotBytes = 4 * 1024 * 1024;
  static const maxChatContextMessages = 24;
}
