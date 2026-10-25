import 'package:flutter_test/flutter_test.dart';
import 'package:mybot/agent/ai_config.dart';
import 'package:mybot/agent/llm_client.dart';
import 'package:mybot/core/constants.dart';
import 'package:mybot/data/models.dart';

void main() {
  group('plan JSON parsing', () {
    test('reads a bare JSON object', () {
      final parsed = parseJsonObject('{"intent":"open whatsapp"}');
      expect(parsed, isNotNull);
      expect(parsed!['intent'], 'open whatsapp');
    });

    test('reads JSON wrapped in a markdown fence', () {
      const raw = 'Sure, here you go:\n```json\n{"steps":[{"bot":"planner"}]}\n```';
      final parsed = parseJsonObject(raw);
      expect(parsed, isNotNull);
      expect((parsed!['steps'] as List).length, 1);
    });

    test('reads JSON with prose around it', () {
      final parsed = parseJsonObject('Result: {"a":1} — done');
      expect(parsed?['a'], 1);
    });

    test('returns null for unreadable output', () {
      expect(parseJsonObject('I could not do that.'), isNull);
    });
  });

  group('safety gate', () {
    test('strict asks before anything that changes state', () {
      expect(RiskLevel.readOnly.needsApproval(SafetyLevel.strict), isFalse);
      expect(RiskLevel.reversible.needsApproval(SafetyLevel.strict), isTrue);
    });

    test('balanced lets reversible run, stops sensitive', () {
      expect(RiskLevel.reversible.needsApproval(SafetyLevel.balanced), isFalse);
      expect(RiskLevel.sensitive.needsApproval(SafetyLevel.balanced), isTrue);
      expect(RiskLevel.irreversible.needsApproval(SafetyLevel.balanced), isTrue);
    });

    test('permissive still stops irreversible', () {
      expect(RiskLevel.sensitive.needsApproval(SafetyLevel.permissive), isFalse);
      expect(
        RiskLevel.irreversible.needsApproval(SafetyLevel.permissive),
        isTrue,
      );
    });

    test('unknown risk strings default to the safer option', () {
      expect(RiskLevelX.parse('something-new'), RiskLevel.sensitive);
      expect(RiskLevelX.parse(null), RiskLevel.sensitive);
    });
  });

  group('AI config', () {
    test('defaults cover every role and provider', () {
      final config = AiConfig.defaults();
      expect(config.roles.length, BotRole.all.length);
      expect(config.providers.length, ProviderKind.values.length);
      for (final role in BotRole.all) {
        expect(config.role(role), isNotNull, reason: 'missing $role');
      }
    });

    test('survives an encode/decode round trip', () {
      final config = AiConfig.defaults();
      final restored = AiConfig.decode(config.encode());
      expect(restored.roles.length, config.roles.length);
      expect(
        restored.role(BotRole.vision)?.model,
        config.role(BotRole.vision)?.model,
      );
    });

    test('falls back to defaults on corrupt json', () {
      final restored = AiConfig.decode('{not json');
      expect(restored.roles.length, BotRole.all.length);
    });
  });

  group('task plan persistence', () {
    test('round trips steps and risk levels', () {
      final plan = TaskPlan(
        id: 'p1',
        intent: 'open whatsapp',
        language: 'roman_ur',
        summary: 'Open WhatsApp',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        steps: [
          PlanStep(
            index: 1,
            bot: BotRole.screenAgent,
            action: 'open_app',
            target: 'com.whatsapp',
            risk: RiskLevel.reversible,
          ),
        ],
      );

      final restored = TaskPlan.fromMap(plan.toMap());
      expect(restored.steps.length, 1);
      expect(restored.steps.first.bot, BotRole.screenAgent);
      expect(restored.steps.first.risk, RiskLevel.reversible);
      expect(restored.language, 'roman_ur');
    });
  });

  group('strategy rules', () {
    test('rules survive storage as a map', () {
      final strategy = Strategy(
        id: 's1',
        name: 'Trend',
        symbol: 'BINANCE:BTCUSDT',
        timeframe: '15',
        rules: {
          'trend_filter': 'price above EMA200',
          'risk': {'max_risk_percent': 1.0},
        },
      );
      final restored = Strategy.fromMap(strategy.toMap());
      expect(restored.rules['trend_filter'], 'price above EMA200');
      expect((restored.rules['risk'] as Map)['max_risk_percent'], 1.0);
    });
  });
}
