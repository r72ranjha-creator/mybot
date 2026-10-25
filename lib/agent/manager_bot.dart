import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../data/models.dart';
import '../data/repositories.dart';
import '../platform/automation_bridge.dart';
import 'ai_config.dart';
import 'llm_client.dart';
import 'prompts.dart';
import 'trading_engine.dart';

class ManagerOutcome {
  ManagerOutcome({
    required this.answer,
    this.plan,
    this.pending,
    this.stopped = false,
    this.failed = false,
  });

  final String answer;
  final TaskPlan? plan;
  final ApprovalRequest? pending;
  final bool stopped;
  final bool failed;
}

/// The controller. One entry point in (`handle`), one answer out.
///
/// Responsibilities: understand the command, plan it, check it against the
/// allow/block list and the safety level, hand each step to the bot that owns
/// it, and merge the pieces back into a single reply.
class ManagerBot {
  ManagerBot({
    required Repositories repositories,
    required AutomationBridge bridge,
    required LlmClient llm,
    required AiConfig config,
    required AppSettings settings,
    void Function(String message)? onProgress,
  })  : _repos = repositories,
        _bridge = bridge,
        _llm = llm,
        _config = config,
        _settings = settings,
        _onProgress = onProgress;

  final Repositories _repos;
  final AutomationBridge _bridge;
  final LlmClient _llm;
  final AiConfig _config;
  final AppSettings _settings;
  final void Function(String message)? _onProgress;
  static const _uuid = Uuid();

  TradingEngine get _trading => TradingEngine(
        repositories: _repos,
        bridge: _bridge,
        llm: _llm,
        config: _config,
      );

  // ------------------------------------------------------------------ public

  Future<ManagerOutcome> handle(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return ManagerOutcome(answer: 'Say what you want me to do.');
    }
    if (_settings.stopRequested) {
      return ManagerOutcome(
        answer: 'Stopped. Clear the stop on the Home screen when you want me '
            'to take commands again.',
        stopped: true,
      );
    }

    final history = await _repos.chat.recent(limit: AppLimits.maxChatContextMessages);
    final userMessage = ChatMessage(
      id: _uuid.v4(),
      role: 'user',
      content: trimmed,
      createdAt: DateTime.now(),
    );
    await _repos.chat.add(userMessage);
    _onProgress?.call('Planning');

    TaskPlan plan;
    try {
      plan = await _buildPlan(trimmed, history);
    } on LlmException catch (error) {
      return _fail(error.message);
    }

    if (plan.steps.isEmpty) {
      plan.steps.add(
        PlanStep(
          index: 1,
          bot: BotRole.manager,
          action: 'answer',
          target: trimmed,
          risk: RiskLevel.readOnly,
        ),
      );
    }

    plan.status = 'running';
    await _repos.plans.save(plan);

    return _executeFrom(
      plan: plan,
      startIndex: 0,
      approvedIndexes: const <int>{},
      results: <String>[],
      original: trimmed,
    );
  }

  /// Called after the user taps Approve or Reject on an approval card.
  Future<ManagerOutcome> resolveApproval({
    required TaskPlan plan,
    required ApprovalRequest approval,
    required bool approved,
  }) async {
    await _repos.approvals.resolve(approval.id, approved ? 'approved' : 'rejected');

    final stepIndex = (approval.payload['stepIndex'] as num?)?.toInt() ?? 0;
    if (!approved) {
      for (final step in plan.steps) {
        if (step.status == StepStatus.pending || step.status == StepStatus.blocked) {
          step.status = StepStatus.skipped;
        }
      }
      plan.status = 'cancelled';
      await _repos.plans.save(plan);
      return ManagerOutcome(
        answer: 'Cancelled. Nothing was changed on your phone.',
        plan: plan,
      );
    }

    if (_settings.stopRequested) {
      plan.status = 'stopped';
      await _repos.plans.save(plan);
      return ManagerOutcome(answer: 'Stopped.', plan: plan, stopped: true);
    }

    plan.status = 'running';
    await _repos.plans.save(plan);

    return _executeFrom(
      plan: plan,
      startIndex: stepIndex,
      approvedIndexes: {stepIndex},
      results: <String>[],
      original: plan.intent,
    );
  }

  // ----------------------------------------------------------------- planning

  Future<TaskPlan> _buildPlan(String input, List<ChatMessage> history) async {
    final context = history
        .where((m) => m.content.trim().isNotEmpty)
        .take(8)
        .map((m) => '${m.role}: ${m.content}')
        .join('\n');

    var intent = input;
    var language = 'en';
    try {
      final parsed = await _llm.complete(
        config: _config,
        role: BotRole.commandParser,
        messages: [
          LlmMessage(role: 'system', text: Prompts.commandParserSystem),
          LlmMessage(
            role: 'user',
            text: '${context.isEmpty ? '' : 'Recent context:\n$context\n\n'}'
                'Command: $input',
          ),
        ],
        jsonMode: true,
        temperature: 0,
        maxTokens: 400,
      );
      final json = parseJsonObject(parsed.text);
      if (json != null) {
        final parsedIntent = (json['intent'] as String?)?.trim();
        if (parsedIntent != null && parsedIntent.isNotEmpty) intent = parsedIntent;
        final parsedLanguage = (json['language'] as String?)?.trim();
        if (parsedLanguage == 'ur' ||
            parsedLanguage == 'roman_ur' ||
            parsedLanguage == 'en') {
          language = parsedLanguage!;
        }
      }
    } catch (_) {
      // Parsing is an optimisation; the planner can work from the raw command.
    }

    _onProgress?.call('Planning steps');

    final planned = await _llm.complete(
      config: _config,
      role: BotRole.planner,
      messages: [
        LlmMessage(role: 'system', text: Prompts.plannerSystem(_settings.safety)),
        LlmMessage(
          role: 'user',
          text: 'Intent: $intent\nRaw command: $input\nLanguage: $language\n'
              '${context.isEmpty ? '' : 'Recent context:\n$context\n'}',
        ),
      ],
      jsonMode: true,
      temperature: 0.2,
    );

    final json = parseJsonObject(planned.text);
    if (json == null) {
      throw LlmException('The planner returned something unreadable.');
    }

    final steps = <PlanStep>[];
    final rawSteps = (json['steps'] as List?) ?? const [];
    var index = 1;
    for (final raw in rawSteps) {
      if (steps.length >= AppLimits.maxStepsPerPlan) break;
      if (raw is! Map) continue;
      final map = raw.cast<String, Object?>();
      final bot = (map['bot'] as String?)?.trim() ?? BotRole.manager;
      if (!BotRole.all.contains(bot)) continue;
      steps.add(PlanStep(
        index: index++,
        bot: bot,
        action: (map['action'] as String?)?.trim().toLowerCase() ?? 'answer',
        target: (map['target'] as String?) ?? '',
        params: (map['params'] as Map?)?.cast<String, Object?>() ?? const {},
        risk: RiskLevelX.parse(map['risk'] as String?),
      ));
    }

    return TaskPlan(
      id: _uuid.v4(),
      intent: intent,
      language: language,
      summary: (json['summary'] as String?) ?? '',
      steps: steps,
      createdAt: DateTime.now(),
    );
  }

  // ---------------------------------------------------------------- execution

  Future<ManagerOutcome> _executeFrom({
    required TaskPlan plan,
    required int startIndex,
    required Set<int> approvedIndexes,
    required List<String> results,
    required String original,
  }) async {
    for (var i = startIndex; i < plan.steps.length; i++) {
      final step = plan.steps[i];
      if (step.status == StepStatus.done) {
        if (step.result.isNotEmpty) results.add(step.result);
        continue;
      }
      if (_settings.stopRequested) {
        step.status = StepStatus.skipped;
        plan.status = 'stopped';
        await _repos.plans.save(plan);
        return ManagerOutcome(
          answer: 'Stopped at step ${step.index}. Nothing else ran.',
          plan: plan,
          stopped: true,
        );
      }

      if (step.risk.needsApproval(_settings.safety) &&
          !approvedIndexes.contains(step.index)) {
        step.status = StepStatus.blocked;
        plan.status = 'awaiting_approval';
        await _repos.plans.save(plan);
        final approval = await _createApproval(plan, step);
        return ManagerOutcome(
          answer: 'I need your okay before step ${step.index}: '
              '${_describeStep(step)}.\n\n${_whySensitive(step)}',
          plan: plan,
          pending: approval,
        );
      }

      step.status = StepStatus.running;
      await _repos.plans.save(plan);
      _onProgress?.call('Step ${step.index}: ${_describeStep(step)}');

      try {
        final result = await _runWithRetry(step, results);
        step.result = result;
        step.status = StepStatus.done;
        results.add(result);
        await _writeLog(step, 'ok', result);
      } on ManagerStop {
        step.status = StepStatus.skipped;
        plan.status = 'stopped';
        await _repos.plans.save(plan);
        return ManagerOutcome(
          answer: 'Stopped at step ${step.index}.',
          plan: plan,
          stopped: true,
        );
      } catch (error) {
        step.status = StepStatus.failed;
        step.result = error.toString();
        results.add('Step ${step.index} failed: $error');
        await _writeLog(step, 'failed', error.toString());
      }
      await _repos.plans.save(plan);
    }

    plan.status = 'done';
    await _repos.plans.save(plan);

    final answer = await _merge(plan, original, results);
    await _repos.chat.add(
      ChatMessage(
        id: _uuid.v4(),
        role: 'assistant',
        content: answer,
        planId: plan.id,
        createdAt: DateTime.now(),
      ),
    );
    return ManagerOutcome(answer: answer, plan: plan);
  }

  Future<String> _runWithRetry(PlanStep step, List<String> prior) async {
    Object? lastError;
    for (var attempt = 0; attempt <= AppLimits.maxRetriesPerStep; attempt++) {
      try {
        return await _dispatch(step, prior);
      } on ManagerStop {
        rethrow;
      } on LlmException {
        rethrow;
      } on ManagerBlocked {
        rethrow;
      } catch (error) {
        lastError = error;
        await Future<void>.delayed(
          Duration(milliseconds: 400 * (attempt + 1)),
        );
      }
    }
    throw ManagerBlocked('$lastError');
  }

  Future<String> _dispatch(PlanStep step, List<String> prior) async {
    if (_settings.stopRequested) throw ManagerStop();

    switch (step.bot) {
      case BotRole.screenAgent:
        return _runScreen(step);
      case BotRole.vision:
        return _runVision(step);
      case BotRole.trading:
        return _runTrading(step);
      case BotRole.manager:
        if (step.action == 'answer' && step.target.isNotEmpty) {
          return _runTextBot(BotRole.writer, step, prior);
        }
        return _runTextBot(BotRole.manager, step, prior);
      default:
        return _runTextBot(step.bot, step, prior);
    }
  }

  Future<String> _runScreen(PlanStep step) async {
    final enabled = await _bridge.isServiceEnabled();
    if (!enabled) {
      throw ManagerBlocked(
        'The accessibility service is off. Turn on MyBot automation in '
        'Settings > Accessibility, then try again.',
      );
    }

    switch (step.action) {
      case 'open_app':
        final requested =
            (step.params['package'] as String?) ?? step.target;
        final package = await _resolvePackage(requested);
        if (package == null) {
          throw ManagerBlocked('I could not find an app called "$requested".');
        }
        final blocked = await _repos.appRules.blockedPackages();
        if (blocked.contains(package)) {
          throw ManagerBlocked('$package is on your blocked list.');
        }
        final opened = await _bridge.openApp(package);
        if (!opened) {
          throw ManagerBlocked('$package would not open on this phone.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        return 'Opened $package.';

      case 'read_screen':
        final nodes = await _bridge.dumpTree();
        final useful = nodes
            .where((n) => n.label.isNotEmpty || n.clickable || n.editable)
            .take(60)
            .map((n) => n.toPrompt())
            .toList();
        if (useful.isEmpty) return 'The screen exposed no readable content.';
        return 'Screen (${nodes.length} nodes): ${jsonEncode(useful)}';

      case 'tap_text':
        final text = (step.params['text'] as String?) ?? step.target;
        final ok = await _bridge.tapText(text);
        if (!ok) throw ManagerBlocked('Nothing on screen matched "$text".');
        await Future<void>.delayed(const Duration(milliseconds: 800));
        return 'Tapped "$text".';

      case 'tap_view_id':
        final viewId = (step.params['viewId'] as String?) ?? step.target;
        final ok = await _bridge.tapViewId(viewId);
        if (!ok) throw ManagerBlocked('No view with id "$viewId".');
        await Future<void>.delayed(const Duration(milliseconds: 800));
        return 'Tapped $viewId.';

      case 'type_text':
        final text = (step.params['text'] as String?) ?? step.target;
        final ok = await _bridge.typeText(text);
        if (!ok) throw ManagerBlocked('No text field was focused.');
        return 'Typed into the focused field.';

      case 'scroll':
        final direction = (step.params['direction'] as String?) ?? 'down';
        await _bridge.scroll(direction);
        await Future<void>.delayed(const Duration(milliseconds: 700));
        return 'Scrolled $direction.';

      case 'back':
        await _bridge.back();
        return 'Went back.';

      case 'screenshot':
        final path = await _bridge.screenshotToFile();
        if (path == null) {
          throw ManagerBlocked('Screenshot unavailable on this device.');
        }
        return 'Screenshot saved to $path.';

      default:
        throw ManagerBlocked('Unsupported screen action "${step.action}".');
    }
  }

  Future<String> _runVision(PlanStep step) async {
    final strategy = await _pickStrategy(step);
    if (strategy == null) {
      throw ManagerBlocked(
        'No saved strategy to check the chart against. Add one on the Trading tab.',
      );
    }
    final result = await _trading.analyzeChart(
      strategy: strategy,
      screenshotPath: step.params['screenshot'] as String?,
    );
    return _formatSignal(result.signal);
  }

  Future<String> _runTrading(PlanStep step) async {
    final strategy = await _pickStrategy(step);
    if (strategy == null) {
      throw ManagerBlocked(
        'No saved strategy yet. Add one on the Trading tab first.',
      );
    }

    switch (step.action) {
      case 'open_tradingview':
        return _trading.prepareChart(strategy);
      case 'analyze_chart':
      default:
        final result = await _trading.runOnDevice(strategy: strategy);
        return _formatSignal(result.signal);
    }
  }

  Future<String> _runTextBot(
    String role,
    PlanStep step,
    List<String> prior,
  ) async {
    final context = prior.isEmpty
        ? ''
        : '\n\nWhat the other bots already found:\n${prior.take(6).join('\n---\n')}';
    final response = await _llm.complete(
      config: _config,
      role: role,
      messages: [
        LlmMessage(role: 'system', text: Prompts.botSystem(role)),
        LlmMessage(
          role: 'user',
          text: 'Task: ${step.action} ${step.target}\n'
              'Details: ${jsonEncode(step.params)}$context',
        ),
      ],
      temperature: 0.4,
    );
    if (response.text.isEmpty) {
      throw ManagerBlocked('${BotRole.labels[role]} returned nothing.');
    }
    return response.text;
  }

  Future<String> _merge(
    TaskPlan plan,
    String original,
    List<String> results,
  ) async {
    if (results.isEmpty) {
      return 'I understood that as: ${plan.intent}. Nothing needed to run.';
    }
    if (results.length == 1 && plan.steps.length == 1) {
      return results.first;
    }

    try {
      final response = await _llm.complete(
        config: _config,
        role: BotRole.writer,
        messages: [
          LlmMessage(
            role: 'system',
            text: Prompts.writerSystem(
              language: _languageName(plan.language),
              userName: '',
            ),
          ),
          LlmMessage(
            role: 'user',
            text: 'What the user asked: $original\n\n'
                'Results from the specialists:\n${results.join('\n---\n')}',
          ),
        ],
        temperature: 0.3,
      );
      if (response.text.isNotEmpty) return response.text;
    } catch (_) {
      // Falling back to the raw results is better than losing them.
    }
    return results.join('\n\n');
  }

  // ------------------------------------------------------------------ helpers

  Future<ApprovalRequest> _createApproval(TaskPlan plan, PlanStep step) async {
    final approval = ApprovalRequest(
      id: _uuid.v4(),
      kind: switch (step.risk) {
        RiskLevel.irreversible => 'irreversible',
        RiskLevel.sensitive => 'sensitive',
        _ => 'step',
      },
      title: 'Step ${step.index}: ${_describeStep(step)}',
      detail: '${_whySensitive(step)}\n\nThe rest of the plan waits until you decide.',
      payload: {
        'planId': plan.id,
        'stepIndex': step.index,
        'bot': step.bot,
        'action': step.action,
        'target': step.target,
      },
      screenshotPath: null,
      createdAt: DateTime.now(),
    );
    await _repos.approvals.create(approval);
    return approval;
  }

  Future<void> _writeLog(PlanStep step, String status, String detail) async {
    await _repos.logs.add(
      ActivityLog(
        id: _uuid.v4(),
        app: step.bot == BotRole.screenAgent ? 'device' : step.bot,
        action: '${step.bot}.${step.action} ${step.target}'.trim(),
        model: _config.role(step.bot)?.model ?? '-',
        status: status,
        detail: detail.length > 400 ? detail.substring(0, 400) : detail,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<Strategy?> _pickStrategy(PlanStep step) async {
    final id = (step.params['strategyId'] as String?) ?? _settings.defaultStrategyId;
    if (id != null) {
      final found = await _repos.trading.strategyById(id);
      if (found != null) return found;
    }
    final all = await _repos.trading.strategies();
    if (all.isEmpty) return null;

    final symbol = (step.params['symbol'] as String?)?.toUpperCase();
    if (symbol != null && symbol.isNotEmpty) {
      for (final strategy in all) {
        if (strategy.symbol.toUpperCase().contains(symbol)) return strategy;
      }
    }
    return all.firstWhere((s) => s.active, orElse: () => all.first);
  }

  Future<String?> _resolvePackage(String requested) async {
    final raw = requested.trim();
    if (raw.isEmpty) return null;
    if (raw.contains('.') && !raw.contains(' ')) return raw;

    final apps = await _bridge.installedApps();
    final needle = raw.toLowerCase();
    for (final app in apps) {
      if (app.label.toLowerCase() == needle) return app.package;
    }
    for (final app in apps) {
      if (app.label.toLowerCase().contains(needle)) return app.package;
    }
    for (final app in apps) {
      if (app.package.toLowerCase().contains(needle)) return app.package;
    }
    return null;
  }

  String _describeStep(PlanStep step) {
    if (step.target.isEmpty) return '${step.bot} ${step.action}';
    return '${step.bot} ${step.action} "${step.target}"';
  }

  String _whySensitive(PlanStep step) {
    return switch (step.risk) {
      RiskLevel.irreversible =>
        'This cannot be undone, so it only runs with your explicit approval.',
      RiskLevel.sensitive =>
        'This can leave a trace outside the app (a message, a post, an order '
            'screen), so it waits for you.',
      RiskLevel.reversible =>
        'Your safety level asks before anything that changes state.',
      RiskLevel.readOnly => 'Read only.',
    };
  }

  String _formatSignal(TradeSignal signal) {
    if (signal.direction == 'no_trade') {
      return 'No trade. ${signal.reason}';
    }
    final entry = signal.entryHigh > signal.entryLow
        ? '${signal.entryLow} - ${signal.entryHigh}'
        : '${signal.entryLow}';
    return '${signal.symbol} ${signal.timeframe}: ${signal.direction.toUpperCase()} '
        '| entry $entry | SL ${signal.stopLoss} | TP ${signal.takeProfit} '
        '| ${signal.confidence}% confidence\n${signal.reason}';
  }

  String _languageName(String code) => switch (code) {
        'ur' => 'Urdu',
        'roman_ur' => 'Roman Urdu',
        _ => 'English',
      };

  ManagerOutcome _fail(String message) {
    final friendly = message.contains('No model answered')
        ? 'I have no working model yet. Add a provider key in AI Settings and '
            'I can start taking commands.'
        : message;
    return ManagerOutcome(answer: friendly, failed: true);
  }
}

/// Internal signal: a step asked us to stop the plan.
class ManagerStop implements Exception {
  const ManagerStop();
}

/// A step refused for a reason the user must see, not retry.
class ManagerBlocked implements Exception {
  ManagerBlocked(this.message);
  final String message;
  @override
  String toString() => message;
}
