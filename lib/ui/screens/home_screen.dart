import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/ai_config.dart';
import '../../core/constants.dart';
import '../../data/models.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final service = ref.watch(serviceEnabledProvider);
    final approvals = ref.watch(pendingApprovalsProvider).valueOrNull ?? const [];
    final plan = ref.watch(activePlanProvider).valueOrNull;
    final settings = ref.watch(appSettingsProvider).valueOrNull ?? AppSettings();
    final chat = ref.watch(chatControllerProvider);
    final config = ref.watch(aiConfigProvider).valueOrNull ?? AiConfig.defaults();
    final serviceOn = service.valueOrNull ?? false;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MyBot',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Manager bot · ${config.roles.length} roles',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            StatusPill(
              label: serviceOn ? 'Automation on' : 'Automation off',
              color: serviceOn ? MyBotTheme.ok : MyBotTheme.warn,
              icon: serviceOn ? Icons.check_circle : Icons.warning_amber_rounded,
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (!serviceOn)
          SectionCard(
            title: 'Turn on phone automation',
            subtitle: 'Without it MyBot can plan, but cannot open apps or read '
                'the screen.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Android > Settings > Accessibility > MyBot automation. '
                  'You can switch it off any time, and MyBot still asks before '
                  'anything that leaves the app.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    await ref.read(automationProvider).openAccessibilitySettings();
                    await Future<void>.delayed(const Duration(seconds: 2));
                    ref.invalidate(serviceEnabledProvider);
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open accessibility settings'),
                ),
              ],
            ),
          ),
        if (settings.stopRequested)
          SectionCard(
            title: 'Stopped',
            subtitle: 'MyBot is refusing new commands.',
            trailing: StatusPill(
              label: 'HALTED',
              color: MyBotTheme.danger,
              icon: Icons.pause_circle,
            ),
            child: FilledButton(
              onPressed: () =>
                  ref.read(chatControllerProvider.notifier).releaseStop(),
              child: const Text('Resume'),
            ),
          ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Now',
          subtitle: chat.busy
              ? (chat.status ?? 'Working')
              : (plan == null
                  ? 'Idle — no task running'
                  : 'Plan: ${plan.intent}'),
          trailing: approvals.isEmpty
              ? null
              : StatusPill(
                  label: '${approvals.length} waiting',
                  color: MyBotTheme.warn,
                  icon: Icons.pending_actions,
                ),
          child: Column(
            children: [
              if (chat.busy) ...[
                BusyBar(label: chat.status ?? 'Working…'),
                const SizedBox(height: 12),
              ],
              if (plan != null)
                _PlanProgress(plan: plan)
              else
                Text(
                  'Ask for something from Chat, or tap a quick command below.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              if (approvals.isNotEmpty) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(selectedTabProvider.notifier).state = 3,
                  icon: const Icon(Icons.verified_user_outlined, size: 18),
                  label: Text('Review ${approvals.length} approval'
                      '${approvals.length == 1 ? '' : 's'}'),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Quick commands',
          subtitle: 'One tap to send to the Manager bot.',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final command in _quickCommands)
                ActionChip(
                  label: Text(command),
                  onPressed: chat.busy
                      ? null
                      : () {
                          ref.read(selectedTabProvider.notifier).state = 1;
                          ref
                              .read(chatControllerProvider.notifier)
                              .send(command);
                        },
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 56,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: settings.stopRequested
                  ? theme.colorScheme.surfaceContainerHighest
                  : MyBotTheme.danger,
              foregroundColor: settings.stopRequested
                  ? theme.colorScheme.onSurface
                  : Colors.white,
            ),
            onPressed: settings.stopRequested
                ? null
                : () =>
                    ref.read(chatControllerProvider.notifier).stopEverything(),
            icon: const Icon(Icons.stop_circle_outlined),
            label: Text(
              settings.stopRequested ? 'Bot stopped' : 'STOP BOT',
              style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.6),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlanProgress extends StatelessWidget {
  const _PlanProgress({required this.plan});

  final TaskPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final step in plan.steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  switch (step.status) {
                    StepStatus.done => Icons.check_circle,
                    StepStatus.running => Icons.play_circle,
                    StepStatus.failed => Icons.error,
                    StepStatus.blocked => Icons.lock_clock,
                    StepStatus.skipped => Icons.remove_circle_outline,
                    StepStatus.pending => Icons.radio_button_unchecked,
                  },
                  size: 18,
                  color: switch (step.status) {
                    StepStatus.done => MyBotTheme.ok,
                    StepStatus.running => MyBotTheme.accent,
                    StepStatus.failed => MyBotTheme.danger,
                    StepStatus.blocked => MyBotTheme.warn,
                    _ => theme.colorScheme.onSurfaceVariant,
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${BotRole.labels[step.bot] ?? step.bot} · ${step.action}'
                    '${step.target.isEmpty ? '' : ' ${step.target}'}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

const _quickCommands = <String>[
  'Open WhatsApp',
  'Screenshot and tell me what is on screen',
  'Check BTCUSDT on 15m against my strategy',
  'What is on my watchlist today?',
];
