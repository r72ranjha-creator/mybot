import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../data/models.dart';
import '../data/repositories.dart';
import '../platform/automation_bridge.dart';
import 'ai_config.dart';
import 'llm_client.dart';
import 'prompts.dart';

class TradeAnalysisResult {
  TradeAnalysisResult({required this.signal, required this.screenshotPath});

  final TradeSignal signal;
  final String? screenshotPath;
}

class TradeAnalysisException implements Exception {
  TradeAnalysisException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The TradingView loop, end to end: open the chart, screenshot it, judge it
/// against the user's saved rules, emit a signal — and stop there.
///
/// The one step this class deliberately does NOT implement is pressing Buy or
/// Sell. That button is the user's, always.
class TradingEngine {
  TradingEngine({
    required Repositories repositories,
    required AutomationBridge bridge,
    required LlmClient llm,
    required AiConfig config,
  })  : _repos = repositories,
        _bridge = bridge,
        _llm = llm,
        _config = config;

  final Repositories _repos;
  final AutomationBridge _bridge;
  final LlmClient _llm;
  final AiConfig _config;
  static const _uuid = Uuid();

  /// Full flow with navigation. Returns the signal; never trades.
  Future<TradeAnalysisResult> runOnDevice({required Strategy strategy}) async {
    await prepareChart(strategy);
    final path = await _bridge.screenshotToFile(prefix: 'tv');
    return analyzeChart(strategy: strategy, screenshotPath: path);
  }

  Future<TradeAnalysisResult> analyzeChart({
    required Strategy strategy,
    String? screenshotPath,
  }) async {
    var png = screenshotPath == null ? null : await _readFile(screenshotPath);
    png ??= await _bridge.screenshot();

    if (png == null) {
      throw TradeAnalysisException(
        'Could not capture the screen. Screenshots need Android 11+ and the '
        'accessibility service switched on.',
      );
    }

    final response = await _llm.complete(
      config: _config,
      role: BotRole.vision,
      messages: [
        LlmMessage(role: 'system', text: Prompts.visionSystem(strategy)),
        LlmMessage(
          role: 'user',
          text: 'Read this TradingView chart for ${strategy.symbol} on '
              '${strategy.timeframe}. Judge it only against the rules.',
          imageBase64: base64Encode(png),
        ),
      ],
      jsonMode: true,
      temperature: 0.1,
    );

    final json = parseJsonObject(response.text);
    if (json == null) {
      throw TradeAnalysisException(
        'The vision model did not return a readable signal.',
      );
    }

    final direction = _normaliseDirection(json['direction']);
    final signal = TradeSignal(
      id: _uuid.v4(),
      symbol: strategy.symbol,
      timeframe: strategy.timeframe,
      direction: direction,
      entryLow: _num(json['entry_low']),
      entryHigh: _num(json['entry_high']),
      stopLoss: _num(json['stop_loss']),
      takeProfit: _num(json['take_profit']),
      confidence: _num(json['confidence']).round().clamp(0, 100),
      reason: (json['reason'] as String?) ?? '',
      strategyId: strategy.id,
      screenshotPath: screenshotPath,
      createdAt: DateTime.now(),
    );

    await _repos.trading.saveSignal(signal);
    await _repos.logs.add(
      ActivityLog(
        id: _uuid.v4(),
        app: 'TradingView',
        action: 'analyze_chart ${strategy.symbol} ${strategy.timeframe}',
        model: '${response.providerId}/${response.model}',
        status: direction,
        detail: signal.reason,
        screenshotPath: screenshotPath,
        createdAt: DateTime.now(),
      ),
    );

    return TradeAnalysisResult(signal: signal, screenshotPath: screenshotPath);
  }

  /// Opens TradingView and lands on the symbol + timeframe. Navigation only —
  /// it stops before the order form.
  Future<String> prepareChart(Strategy strategy) async {
    final opened = await _bridge.openApp('com.tradingview.tradingviewapp');
    if (!opened) {
      final url = 'https://www.tradingview.com/chart/?symbol=${strategy.symbol}';
      final fallback = await _bridge.openUrl(url);
      if (!fallback) {
        throw TradeAnalysisException(
          'TradingView is not installed and no browser could be opened.',
        );
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    await _bridge.tapText('Search', exact: false);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await _bridge.typeText(strategy.symbol);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    await _bridge.tapText(strategy.symbol.split(':').last, exact: false);
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    await _bridge.tapText(strategy.timeframe, exact: true);
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    await _repos.logs.add(
      ActivityLog(
        id: _uuid.v4(),
        app: 'TradingView',
        action: 'open_chart ${strategy.symbol} ${strategy.timeframe}',
        model: '-',
        status: 'ok',
        createdAt: DateTime.now(),
      ),
    );

    return 'TradingView is open on ${strategy.symbol} (${strategy.timeframe}). '
        'The order screen was not touched.';
  }

  Future<Uint8List?> _readFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  String _normaliseDirection(Object? raw) {
    final value = (raw as String? ?? '').toLowerCase().trim();
    if (value.contains('long') || value.contains('buy')) return 'long';
    if (value.contains('short') || value.contains('sell')) return 'short';
    return 'no_trade';
  }

  double _num(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.replaceAll(',', '')) ?? 0;
    return 0;
  }
}
