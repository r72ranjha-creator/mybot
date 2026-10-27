import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../agent/ai_config.dart';
import '../../agent/trading_engine.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

class TradingScreen extends ConsumerStatefulWidget {
  const TradingScreen({super.key});

  @override
  ConsumerState<TradingScreen> createState() => _TradingScreenState();
}

class _TradingScreenState extends ConsumerState<TradingScreen> {
  bool _running = false;
  String? _status;

  static const _defaultRules = {
    'trend_filter': 'price above EMA200',
    'entry_trigger': 'close above previous swing high',
    'invalidation': 'close back below EMA50',
    'volume': 'entry bar volume above 20-bar average',
    'risk': {'max_risk_percent': 1.0, 'min_reward_risk': 2.0},
    'avoid': ['news within 30 minutes', 'illiquid session'],
  };

  Future<void> _analyze(Strategy strategy) async {
    setState(() {
      _running = true;
      _status = 'Opening TradingView and reading the chart…';
    });
    try {
      final config = await ref.read(aiConfigProvider.future);
      final engine = TradingEngine(
        repositories: ref.read(repositoriesProvider),
        bridge: ref.read(automationProvider),
        llm: ref.read(llmClientProvider),
        config: config,
      );
      final result = await engine.runOnDevice(strategy: strategy);
      ref.invalidate(signalsProvider);
      ref.invalidate(logsProvider);
      await _notifySignal(result.signal);
      if (!mounted) return;
      setState(() => _status = null);
      _showSignal(result.signal);
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _showSignal(TradeSignal signal) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${signal.symbol} · ${signal.direction.toUpperCase()}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Entry: ${signal.entryLow} – ${signal.entryHigh}'),
            Text('Stop loss: ${signal.stopLoss}'),
            Text('Take profit: ${signal.takeProfit}'),
            Text('Confidence: ${signal.confidence}%'),
            const SizedBox(height: 10),
            Text(signal.reason),
            const SizedBox(height: 14),
            const Text(
              'MyBot never places the order. Open TradingView and press the '
              'button yourself if you agree.',
              style: TextStyle(fontSize: 12, color: MyBotTheme.warn),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Create or edit a strategy. Invalid JSON is refused with the reason
  /// instead of being silently replaced by the defaults.
  Future<void> _strategyDialog({Strategy? existing}) async {
    final nameController =
        TextEditingController(text: existing?.name ?? 'My strategy');
    final symbolController =
        TextEditingController(text: existing?.symbol ?? 'BINANCE:BTCUSDT');
    final timeframeController =
        TextEditingController(text: existing?.timeframe ?? '15');
    final rulesController = TextEditingController(
      text: existing == null
          ? const JsonEncoder.withIndent('  ').convert(_defaultRules)
          : const JsonEncoder.withIndent('  ').convert(existing.rules),
    );
    var error = '';

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'New strategy' : 'Edit strategy'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: symbolController,
                  decoration: const InputDecoration(
                    labelText: 'Symbol',
                    hintText: 'BINANCE:BTCUSDT',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: timeframeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Timeframe minutes',
                    hintText: '5, 15, 60, 240',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: rulesController,
                  minLines: 6,
                  maxLines: 12,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: const InputDecoration(labelText: 'Rules (JSON)'),
                ),
                if (error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      error,
                      style: const TextStyle(
                        fontSize: 12,
                        color: MyBotTheme.danger,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final symbol = symbolController.text.trim();
                final timeframe = timeframeController.text.trim();
                final decoded = _parseRules(rulesController.text);
                final problem = name.isEmpty
                    ? 'Name khali nahi ho sakta.'
                    : symbol.isEmpty
                        ? 'Symbol likhein.'
                        : timeframe.isEmpty
                            ? 'Timeframe likhein (minutes).'
                            : decoded == null
                                ? 'Rules valid JSON object nahi hain.'
                                : decoded.isEmpty
                                    ? 'Rules khali nahi ho sakte.'
                                    : '';
                if (problem.isNotEmpty) {
                  setDialogState(() => error = problem);
                  return;
                }
                Navigator.of(context).pop(true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    final name = nameController.text.trim();
    final symbol = symbolController.text.trim();
    final timeframe = timeframeController.text.trim();
    final rules = _parseRules(rulesController.text) ?? _defaultRules;
    nameController.dispose();
    symbolController.dispose();
    timeframeController.dispose();
    rulesController.dispose();

    if (saved != true) return;
    await ref.read(repositoriesProvider).trading.saveStrategy(
          Strategy(
            id: existing?.id ?? const Uuid().v4(),
            name: name,
            symbol: symbol.toUpperCase(),
            timeframe: timeframe,
            rules: rules,
            active: existing?.active ?? true,
          ),
        );
    ref.invalidate(strategiesProvider);
  }

  Map<String, Object?>? _parseRules(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return decoded.cast<String, Object?>();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Sends today's analysis a local notification, so a signal found while the
  /// app was in the background is not lost.
  Future<void> _notifySignal(TradeSignal signal) async {
    final settings = ref.read(appSettingsProvider).valueOrNull;
    if (settings == null || !settings.notifications) return;
    final body = signal.direction == 'no_trade'
        ? '${signal.symbol}: no trade — ${signal.reason}'
        : '${signal.symbol} ${signal.direction.toUpperCase()} · '
            '${signal.confidence}% confidence';
    await ref.read(notifierProvider).show(
          title: 'New signal',
          body: body,
        );
  }

  Future<void> _addWatch() async {
    final symbolController = TextEditingController();
    final timeframeController = TextEditingController(text: '15');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add to watchlist'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: symbolController,
              decoration: const InputDecoration(labelText: 'Symbol'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: timeframeController,
              decoration: const InputDecoration(labelText: 'Timeframe'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    if (symbolController.text.trim().isEmpty) return;
    await ref.read(repositoriesProvider).trading.saveWatch(
          WatchlistEntry(
            id: const Uuid().v4(),
            symbol: symbolController.text.trim().toUpperCase(),
            timeframe: timeframeController.text.trim(),
          ),
        );
    ref.invalidate(watchlistProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strategies = ref.watch(strategiesProvider);
    final signals = ref.watch(signalsProvider);
    final watchlist = ref.watch(watchlistProvider);
    final settings = ref.watch(appSettingsProvider).valueOrNull ?? AppSettings();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Row(
          children: [
            Text(
              'Trading',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            IconButton(
              onPressed: () {
                ref.invalidate(strategiesProvider);
                ref.invalidate(signalsProvider);
                ref.invalidate(watchlistProvider);
              },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_running) BusyBar(label: _status ?? 'Working…'),
        if (_running) const SizedBox(height: 12),
        SectionCard(
          title: 'Strategies',
          subtitle: 'Your rules, as JSON. The vision model judges the chart '
              'against exactly these.',
          trailing: IconButton(
            tooltip: 'New strategy',
            onPressed: () => _strategyDialog(),
            icon: const Icon(Icons.add_circle_outline),
          ),
          child: strategies.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (error, _) => Text('$error'),
            data: (items) {
              if (items.isEmpty) {
                return Text(
                  'No strategy yet. Add one so MyBot knows what "good setup" '
                  'means to you.',
                  style: theme.textTheme.bodySmall,
                );
              }
              return Column(
                children: [
                  for (final strategy in items)
                    _StrategyTile(
                      strategy: strategy,
                      disabled: _running,
                      isDefault: settings.defaultStrategyId == strategy.id,
                      onSetDefault: () => ref
                          .read(appSettingsProvider.notifier)
                          .patch(
                            (current) => current.copyWith(
                              defaultStrategyId: strategy.id,
                            ),
                          ),
                      onEdit: () => _strategyDialog(existing: strategy),
                      onAnalyze: () => _analyze(strategy),
                      onOpenChart: () async {
                        final config = await ref.read(aiConfigProvider.future);
                        final engine = TradingEngine(
                          repositories: ref.read(repositoriesProvider),
                          bridge: ref.read(automationProvider),
                          llm: ref.read(llmClientProvider),
                          config: config,
                        );
                        try {
                          final note = await engine.prepareChart(strategy);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(note)),
                          );
                        } catch (error) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('$error')),
                          );
                        }
                      },
                      onDelete: () async {
                        await ref
                            .read(repositoriesProvider)
                            .trading
                            .deleteStrategy(strategy.id);
                        ref.invalidate(strategiesProvider);
                      },
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Watchlist',
          trailing: IconButton(
            onPressed: _addWatch,
            icon: const Icon(Icons.add_circle_outline),
          ),
          child: watchlist.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (error, _) => Text('$error'),
            data: (items) {
              if (items.isEmpty) {
                return Text('Nothing watched yet.',
                    style: theme.textTheme.bodySmall);
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in items)
                    InputChip(
                      label: Text('${entry.symbol} · ${entry.timeframe}m'),
                      onPressed: () async {
                        final all =
                            ref.read(strategiesProvider).valueOrNull ?? const [];
                        if (entry.symbol.isEmpty) return;
                        final match = all.where((s) =>
                            entry.symbol.contains(s.symbol.split(':').last));
                        if (match.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Add a strategy for ${entry.symbol} first.',
                              ),
                            ),
                          );
                          return;
                        }
                        await _analyze(match.first);
                      },
                      onDeleted: () async {
                        await ref
                            .read(repositoriesProvider)
                            .trading
                            .removeWatch(entry.id);
                        ref.invalidate(watchlistProvider);
                      },
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Signals & journal',
          child: signals.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (error, _) => Text('$error'),
            data: (items) {
              if (items.isEmpty) {
                return Text('No signals yet.',
                    style: theme.textTheme.bodySmall);
              }
              return Column(
                children: [
                  for (final signal in items.take(20))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${signal.symbol} · ${signal.direction.toUpperCase()}',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${signal.confidence}% · ${relativeTime(signal.createdAt)}\n'
                        '${signal.reason}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: StatusPill(
                        label: signal.status,
                        color: signal.direction == 'no_trade'
                            ? MyBotTheme.warn
                            : MyBotTheme.accent,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StrategyTile extends StatelessWidget {
  const _StrategyTile({
    required this.strategy,
    required this.onAnalyze,
    required this.onOpenChart,
    required this.onDelete,
    required this.onEdit,
    required this.onSetDefault,
    required this.isDefault,
    required this.disabled,
  });

  final Strategy strategy;
  final VoidCallback onAnalyze;
  final VoidCallback onOpenChart;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final VoidCallback onSetDefault;
  final bool isDefault;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        strategy.name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (isDefault)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: StatusPill(
                          label: 'default',
                          color: MyBotTheme.accent,
                        ),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'default') onSetDefault();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit rules')),
                  if (!isDefault)
                    const PopupMenuItem(
                      value: 'default',
                      child: Text('Use as default'),
                    ),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          Text(
            '${strategy.symbol} · ${strategy.timeframe}m · '
            '${strategy.rules.length} rules',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: disabled ? null : onAnalyze,
                  icon: const Icon(Icons.analytics_outlined, size: 18),
                  label: const Text('Analyse chart'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: disabled ? null : onOpenChart,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
