import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybot/agent/ai_config.dart';
import 'package:mybot/core/plan_resume.dart';
import 'package:mybot/data/models.dart';
import 'package:mybot/media/media_pipeline.dart';
import 'package:mybot/ui/theme.dart';
import 'package:mybot/ui/widgets/common.dart';

TaskPlan planWith(int stepCount) {
  final plan = TaskPlan(
    id: 'plan-1',
    intent: 'test',
    language: 'en',
    steps: <PlanStep>[],
    createdAt: DateTime(2026, 1, 1),
  );
  for (var i = 1; i <= stepCount; i++) {
    plan.steps.add(
      PlanStep(
        index: i,
        bot: 'manager',
        action: 'answer',
        target: 'step $i',
      ),
    );
  }
  return plan;
}

void main() {
  group('approval resume position', () {
    test('approving step 1 resumes at the first step, not the second', () {
      final plan = planWith(3);
      final position = PlanResume.positionFor(plan, {
        'stepIndex': 0,
        'stepNumber': 1,
      });
      expect(position, 0);
      expect(plan.steps[position!].index, 1);
    });

    test('approving step 2 resumes at the second step', () {
      final plan = planWith(3);
      final position = PlanResume.positionFor(plan, {
        'stepIndex': 1,
        'stepNumber': 2,
      });
      expect(position, 1);
    });

    test('an old payload that stored the 1-based number still resolves', () {
      final plan = planWith(3);
      final position = PlanResume.positionFor(plan, {'stepIndex': 1});
      expect(position, 0);
    });

    test('a step no longer in the plan resolves to null', () {
      final plan = planWith(2);
      expect(PlanResume.positionFor(plan, {'stepIndex': 9}), isNull);
      expect(PlanResume.positionFor(plan, const {}), isNull);
    });
  });

  group('settings persistence', () {
    test('a stop survives being saved and reloaded', () {
      final settings = AppSettings().copyWith(stopRequested: true);
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.stopRequested, isTrue);
    });

    test('a fresh install is not stopped', () {
      expect(AppSettings.fromJson(const {}).stopRequested, isFalse);
    });

    test('the default strategy can be cleared as well as set', () {
      final set = AppSettings().copyWith(defaultStrategyId: 's-1');
      expect(set.defaultStrategyId, 's-1');
      final cleared = set.copyWith(clearDefaultStrategy: true);
      expect(cleared.defaultStrategyId, isNull);
    });

    test('language and order-tap preference round trip', () {
      final settings = AppSettings()
          .copyWith(language: 'roman_ur', allowOrderTap: true);
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.language, 'roman_ur');
      expect(restored.allowOrderTap, isTrue);
    });
  });

  group('file types', () {
    test('a pdf is labelled as a pdf, not as its extension', () {
      expect(MediaPipeline.mimeForPath('/tmp/report.pdf'), 'application/pdf');
    });

    test('a photo keeps its real image type', () {
      expect(MediaPipeline.mimeForPath('/tmp/shot.PNG'), 'image/png');
      expect(MediaPipeline.mimeForPath('/tmp/shot.jpeg'), 'image/jpeg');
    });

    test('an unknown extension has no type instead of a wrong one', () {
      expect(MediaPipeline.mimeForPath('/tmp/thing.zzz'), isNull);
    });
  });

  group('relative time', () {
    test('says just now for a fresh timestamp', () {
      expect(relativeTime(DateTime.now()), 'just now');
    });

    test('switches to minutes and hours', () {
      expect(
        relativeTime(DateTime.now().subtract(const Duration(minutes: 5))),
        '5m ago',
      );
      expect(
        relativeTime(DateTime.now().subtract(const Duration(hours: 3))),
        '3h ago',
      );
    });
  });

  group('shared widgets', () {
    testWidgets('a status pill renders its label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: MyBotTheme.light(),
          home: const Scaffold(
            body: StatusPill(label: 'pending', color: MyBotTheme.warn),
          ),
        ),
      );
      expect(find.text('pending'), findsOneWidget);
    });

    testWidgets('an empty state renders its body', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: MyBotTheme.light(),
          home: const Scaffold(
            body: EmptyState(
              icon: Icons.verified_user_outlined,
              title: 'Nothing waiting',
              body: 'Approvals land here.',
            ),
          ),
        ),
      );
      expect(find.text('Nothing waiting'), findsOneWidget);
      expect(find.text('Approvals land here.'), findsOneWidget);
      expect(find.byIcon(Icons.verified_user_outlined), findsOneWidget);
    });

    testWidgets('a section card shows a trailing action', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: MyBotTheme.light(),
          home: Scaffold(
            body: SectionCard(
              title: 'Strategies',
              trailing: IconButton(
                onPressed: () => tapped = true,
                icon: const Icon(Icons.add),
              ),
              child: const Text('body'),
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(tapped, isTrue);
      expect(find.text('body'), findsOneWidget);
    });
  });
}
