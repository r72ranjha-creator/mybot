import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../agent/ai_config.dart';
import '../agent/llm_client.dart';
import '../agent/manager_bot.dart';
import '../agent/research/research_engine.dart';
import '../core/halt.dart';
import '../core/token_budget.dart';
import '../data/db.dart';
import '../data/media_models.dart';
import '../data/models.dart';
import '../data/repositories.dart';
import '../data/research_models.dart';
import '../data/secure_store.dart';
import '../media/media_pipeline.dart';
import '../platform/automation_bridge.dart';
import '../platform/notifier.dart';
import '../voice/stt_service.dart';
import '../voice/tts_service.dart';

final selectedTabProvider = StateProvider<int>((ref) => 0);

final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase.instance);

final repositoriesProvider = Provider<Repositories>(
  (ref) => Repositories(ref.watch(databaseProvider)),
);

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());

final llmClientProvider = Provider<LlmClient>((ref) => LlmClient(
      repositories: ref.watch(repositoriesProvider),
      secure: ref.watch(secureStoreProvider),
    ));

final automationProvider =
    Provider<AutomationBridge>((ref) => AutomationBridge());

final sttProvider = Provider<SttService>((ref) => SttService());

final imagePickerProvider = Provider<ImagePicker>((ref) => ImagePicker());

final ttsProvider = Provider<TtsService>((ref) => TtsService());

final mediaPipelineProvider = Provider<MediaPipeline>(
  (ref) => MediaPipeline(repositories: ref.watch(repositoriesProvider)),
);

final notifierProvider = Provider<LocalNotifier>((ref) => LocalNotifier());

/// Which project the composer is scoped to, if any.
final activeProjectProvider = StateProvider<String?>((ref) => null);

/// Search provider order. Keys themselves live in the Keystore.
final searchOrderProvider = Provider<List<String>>((ref) {
  return const ['tavily', 'perplexity', 'brave', 'serper'];
});

final researchEngineProvider = Provider<ResearchEngine>((ref) {
  final config = ref.watch(aiConfigProvider).valueOrNull ?? AiConfig.defaults();
  return ResearchEngine(
    repositories: ref.watch(repositoriesProvider),
    llm: ref.watch(llmClientProvider),
    config: config,
    secure: ref.watch(secureStoreProvider),
    order: ref.watch(searchOrderProvider),
  );
});

final projectsProvider = FutureProvider<List<Project>>(
  (ref) => ref.watch(repositoriesProvider).projects.all(),
);

final projectReportsProvider = FutureProvider.family<List<ResearchReport>, String?>(
  (ref, projectId) => ref.watch(repositoriesProvider).research.recent(
        projectId: projectId,
        limit: 30,
      ),
);

final mediaLibraryProvider = FutureProvider<List<MediaFile>>(
  (ref) => ref.watch(repositoriesProvider).media.recent(limit: 60),
);

// ------------------------------------------------------------------- config

class AiConfigNotifier extends AsyncNotifier<AiConfig> {
  @override
  Future<AiConfig> build() async {
    final repos = ref.watch(repositoriesProvider);
    final raw = await repos.settings.get(AiConfig.storageKey);
    return AiConfig.decode(raw);
  }

  Future<void> _persist(AiConfig config) async {
    final repos = ref.read(repositoriesProvider);
    await repos.settings.put(AiConfig.storageKey, config.encode());
    state = AsyncData(config);
  }

  Future<void> setRole(RoleConfig role) async {
    final current = await future;
    await _persist(current.withRole(role));
  }

  Future<void> setProvider(ProviderConfig provider) async {
    final current = await future;
    await _persist(current.withProvider(provider));
  }

  Future<void> reset() async => _persist(AiConfig.defaults());
}

final aiConfigProvider =
    AsyncNotifierProvider<AiConfigNotifier, AiConfig>(AiConfigNotifier.new);

class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final repos = ref.watch(repositoriesProvider);
    final raw = await repos.settings.get(AppSettings.storageKey);
    if (raw == null || raw.trim().isEmpty) {
      Halt.restore(false);
      return AppSettings();
    }
    try {
      final settings = AppSettings.fromJson(
        (jsonDecodeMap(raw)).cast<String, Object?>(),
      );
      // Restore the safety state before the first command can be handled.
      Halt.restore(settings.stopRequested);
      return settings;
    } catch (_) {
      Halt.restore(false);
      return AppSettings();
    }
  }

  Future<void> _persist(AppSettings settings) async {
    final repos = ref.read(repositoriesProvider);
    await repos.settings.put(
      AppSettings.storageKey,
      encodeJson(settings.toJson()),
    );
    Halt.restore(settings.stopRequested);
    state = AsyncData(settings);
  }

  Future<void> patch(AppSettings Function(AppSettings) change) async {
    final current = state.valueOrNull ?? AppSettings();
    await _persist(change(current));
  }

  Future<void> setStop(bool stop) =>
      patch((s) => s.copyWith(stopRequested: stop));
}

final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);

// ------------------------------------------------------------------- budget

/// Daily token ceilings. Stored separately from the rest of the settings so a
/// budget reset never touches routing or keys.
class TokenBudgetNotifier extends AsyncNotifier<TokenBudget> {
  @override
  Future<TokenBudget> build() async {
    final raw = await ref
        .watch(repositoriesProvider)
        .settings
        .get(TokenBudget.storageKey);
    return TokenBudget.decode(raw);
  }

  Future<void> _persist(TokenBudget budget) async {
    await ref
        .read(repositoriesProvider)
        .settings
        .put(TokenBudget.storageKey, budget.encode());
    state = AsyncData(budget);
  }

  Future<void> setDefaultDaily(int tokens) async {
    final current = await future;
    await _persist(
      TokenBudget(perRole: current.perRole, defaultDaily: tokens),
    );
  }

  Future<void> setRoleDaily(String role, int tokens) async {
    final current = await future;
    await _persist(current.withRole(role, tokens));
  }

  Future<void> clear() async => _persist(TokenBudget.off);
}

final tokenBudgetProvider =
    AsyncNotifierProvider<TokenBudgetNotifier, TokenBudget>(
  TokenBudgetNotifier.new,
);

final tokensTodayProvider = FutureProvider<int>(
  (ref) => ref.watch(repositoriesProvider).usage.tokensToday(),
);

// --------------------------------------------------------------- live data

final serviceEnabledProvider = FutureProvider<bool>(
  (ref) => ref.watch(automationProvider).isServiceEnabled(),
);

final pendingApprovalsProvider = FutureProvider<List<ApprovalRequest>>(
  (ref) => ref.watch(repositoriesProvider).approvals.pending(),
);

final activePlanProvider = FutureProvider<TaskPlan?>(
  (ref) => ref.watch(repositoriesProvider).plans.active(),
);

final logsProvider = FutureProvider<List<ActivityLog>>(
  (ref) => ref.watch(repositoriesProvider).logs.recent(),
);

final installedAppsProvider = FutureProvider<List<InstalledApp>>(
  (ref) => ref.watch(automationProvider).installedApps(),
);

final appRulesProvider = FutureProvider<List<AppRule>>(
  (ref) => ref.watch(repositoriesProvider).appRules.all(),
);

final strategiesProvider = FutureProvider<List<Strategy>>(
  (ref) => ref.watch(repositoriesProvider).trading.strategies(),
);

final signalsProvider = FutureProvider<List<TradeSignal>>(
  (ref) => ref.watch(repositoriesProvider).trading.signals(),
);

final watchlistProvider = FutureProvider<List<WatchlistEntry>>(
  (ref) => ref.watch(repositoriesProvider).trading.watchlist(),
);

final usageTotalsProvider = FutureProvider<Map<String, int>>(
  (ref) => ref.watch(repositoriesProvider).usage.totals(),
);

final usageByRoleProvider = FutureProvider<List<Map<String, Object?>>>(
  (ref) => ref.watch(repositoriesProvider).usage.byRole(),
);

// ------------------------------------------------------------------ chat

class ChatState {
  ChatState({
    this.messages = const [],
    this.busy = false,
    this.status,
    this.pendingApproval,
    this.lastFailed = false,
    this.report,
    this.language = 'en',
  });

  final List<ChatMessage> messages;
  final bool busy;
  final String? status;
  final ApprovalRequest? pendingApproval;
  final bool lastFailed;
  final ResearchReport? report;

  /// Language of the last reply, so it is read aloud with a matching voice.
  final String language;

  static final ChatState empty = ChatState();

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? busy,
    String? status,
    bool clearStatus = false,
    ApprovalRequest? pendingApproval,
    bool clearApproval = false,
    bool? lastFailed,
    ResearchReport? report,
    bool clearReport = false,
    String? language,
  }) =>
      ChatState(
        messages: messages ?? this.messages,
        busy: busy ?? this.busy,
        status: clearStatus ? null : (status ?? this.status),
        pendingApproval:
            clearApproval ? null : (pendingApproval ?? this.pendingApproval),
        lastFailed: lastFailed ?? this.lastFailed,
        report: clearReport ? null : (report ?? this.report),
        language: language ?? this.language,
      );
}

class ChatController extends Notifier<ChatState> {
  @override
  ChatState build() {
    Future.microtask(_load);
    return ChatState.empty;
  }

  Future<void> _load() async {
    final repos = ref.read(repositoriesProvider);
    final messages = await repos.chat.recent(limit: 80);
    state = state.copyWith(messages: messages);
  }

  Future<void> refresh() => _load();

  Future<void> send(
    String text, {
    List<MediaFile> attachments = const [],
    String? projectId,
  }) async {
    if (state.busy) return;
    final config = await ref.read(aiConfigProvider.future);
    final settings = await ref.read(appSettingsProvider.future);
    final repos = ref.read(repositoriesProvider);

    state = state.copyWith(
      busy: true,
      clearApproval: true,
      status: 'Thinking',
      lastFailed: false,
      messages: [
        ...state.messages,
        ChatMessage(
          id: 'local-${DateTime.now().microsecondsSinceEpoch}',
          role: 'user',
          content: text,
          createdAt: DateTime.now(),
        ),
      ],
    );

    final manager = ManagerBot(
      repositories: repos,
      bridge: ref.read(automationProvider),
      llm: ref.read(llmClientProvider),
      config: config,
      settings: settings,
      onProgress: (message) => state = state.copyWith(status: message),
      research: ref.read(researchEngineProvider),
    );

    try {
      final outcome = await manager.handle(
        text,
        attachments: attachments,
        projectId: projectId,
      );
      final refreshed = await repos.chat.recent(limit: 80);
      state = state.copyWith(
        busy: false,
        clearStatus: true,
        messages: refreshed,
        pendingApproval: outcome.pending,
        lastFailed: outcome.failed,
        report: outcome.report,
        clearReport: outcome.report == null,
        language: outcome.plan?.language,
      );
      _refreshCounters();
      if (outcome.pending != null && settings.notifications) {
        // The approval may have been requested while the user was elsewhere.
        await ref.read(notifierProvider).show(
              title: 'Approval needed',
              body: outcome.pending!.title,
            );
        ref.invalidate(pendingApprovalsProvider);
      }
    } catch (error) {
      state = state.copyWith(
        busy: false,
        clearStatus: true,
        lastFailed: true,
        messages: [
          ...state.messages,
          ChatMessage(
            id: 'err-${DateTime.now().microsecondsSinceEpoch}',
            role: 'assistant',
            content: 'That failed: $error',
            createdAt: DateTime.now(),
          ),
        ],
      );
    }
  }

  Future<void> decide(ApprovalRequest approval, bool approved) async {
    if (state.busy) return;
    final repos = ref.read(repositoriesProvider);
    final planId = approval.payload['planId'] as String?;
    final plan = planId == null ? null : await repos.plans.byId(planId);
    if (plan == null) {
      await repos.approvals.resolve(approval.id, approved ? 'approved' : 'rejected');
      state = state.copyWith(clearApproval: true);
      return;
    }

    final config = await ref.read(aiConfigProvider.future);
    final settings = await ref.read(appSettingsProvider.future);

    state = state.copyWith(
      busy: true,
      clearApproval: true,
      status: approved ? 'Running the approved step' : 'Cancelling',
    );

    final manager = ManagerBot(
      repositories: repos,
      bridge: ref.read(automationProvider),
      llm: ref.read(llmClientProvider),
      config: config,
      settings: settings,
      onProgress: (message) => state = state.copyWith(status: message),
      research: ref.read(researchEngineProvider),
    );

    try {
      final outcome = await manager.resolveApproval(
        plan: plan,
        approval: approval,
        approved: approved,
      );
      final refreshed = await repos.chat.recent(limit: 80);
      state = state.copyWith(
        busy: false,
        clearStatus: true,
        messages: refreshed,
        pendingApproval: outcome.pending,
        lastFailed: outcome.failed,
        language: outcome.plan?.language,
      );
      _refreshCounters();
    } catch (error) {
      // A failed approval must say so: silence left the user staring at a
      // screen where nothing had happened and nothing explained why.
      state = state.copyWith(
        busy: false,
        clearStatus: true,
        lastFailed: true,
        messages: [
          ...state.messages,
          ChatMessage(
            id: 'err-${DateTime.now().microsecondsSinceEpoch}',
            role: 'assistant',
            content: 'Could not finish that step: $error',
            createdAt: DateTime.now(),
          ),
        ],
      );
      _refreshCounters();
    }
  }

  /// The STOP button on Home: freeze the current plan and refuse new work.
  Future<void> stopEverything() async {
    // Set the live flag first: a plan that is running right now checks it
    // before its next step.
    Halt.request();
    await ref.read(appSettingsProvider.notifier).setStop(true);
    state = state.copyWith(status: 'Stopped', busy: false, clearApproval: true);
    _refreshCounters();
  }

  Future<void> releaseStop() async {
    Halt.clear();
    await ref.read(appSettingsProvider.notifier).setStop(false);
    state = state.copyWith(clearStatus: true);
  }

  void _refreshCounters() {
    ref.invalidate(pendingApprovalsProvider);
    ref.invalidate(activePlanProvider);
    ref.invalidate(logsProvider);
    ref.invalidate(signalsProvider);
  }
}

final chatControllerProvider =
    NotifierProvider<ChatController, ChatState>(ChatController.new);

Map<String, Object?> jsonDecodeMap(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is Map<String, Object?>) return decoded;
  if (decoded is Map) return decoded.cast<String, Object?>();
  return <String, Object?>{};
}
