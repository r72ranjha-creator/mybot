import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'ai_settings_screen.dart';
import 'apps_screen.dart';
import 'projects_screen.dart';
import 'logs_screen.dart';
import 'settings_screen.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final serviceOn = ref.watch(serviceEnabledProvider).valueOrNull ?? false;
    final logs = ref.watch(logsProvider).valueOrNull ?? const [];
    final failed = logs.where((log) => log.status == 'failed').length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          'More',
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        SectionCard(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              _Entry(
                icon: Icons.apps,
                title: 'Apps',
                subtitle: 'Allow or block, and see what ran',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AppsScreen()),
                ),
              ),
              _Entry(
                icon: Icons.receipt_long_outlined,
                title: 'Logs',
                subtitle: failed == 0
                    ? 'Every action, model and screenshot'
                    : '$failed failed action${failed == 1 ? '' : 's'} to review',
                badge: failed == 0 ? null : '$failed',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LogsScreen()),
                ),
              ),
              _Entry(
                icon: Icons.folder_outlined,
                title: 'Projects',
                subtitle: 'Chats, reports aur files project ke andar',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProjectsScreen()),
                ),
              ),
              _Entry(
                icon: Icons.travel_explore,
                title: 'Research reports',
                subtitle: 'Sources ke sath saved research',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ResearchReportsScreen(),
                  ),
                ),
              ),
              _Entry(
                icon: Icons.tune,
                title: 'AI settings',
                subtitle: 'Keys, per-role models, fallback order',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AiSettingsScreen()),
                ),
              ),
              _Entry(
                icon: Icons.settings_outlined,
                title: 'Settings',
                subtitle: 'Language, theme, safety, backup',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Phone automation',
          subtitle: serviceOn ? 'Connected' : 'Not connected',
          trailing: StatusPill(
            label: serviceOn ? 'ON' : 'OFF',
            color: serviceOn ? MyBotTheme.ok : MyBotTheme.warn,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                serviceOn
                    ? 'MyBot can read the screen and tap for you. Sensitive '
                        'steps still wait for your tap.'
                    : 'Turn on MyBot automation in Android accessibility '
                        'settings to let it act on the screen.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await ref
                            .read(automationProvider)
                            .openAccessibilitySettings();
                        await Future<void>.delayed(const Duration(seconds: 2));
                        ref.invalidate(serviceEnabledProvider);
                      },
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('Accessibility'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => ref.invalidate(serviceEnabledProvider),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badge != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: StatusPill(label: badge!, color: MyBotTheme.danger),
            ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap,
    );
  }
}
