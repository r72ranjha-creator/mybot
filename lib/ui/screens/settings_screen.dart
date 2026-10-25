import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/ai_config.dart';
import '../../core/constants.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(appSettingsProvider).valueOrNull ?? AppSettings();
    final notifier = ref.read(appSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          SectionCard(
            title: 'Language',
            subtitle: 'What MyBot answers in when you do not make it obvious.',
            child: Column(
              children: [
                for (final option in const [
                  ('auto', 'Match my message'),
                  ('en', 'English'),
                  ('ur', '\u0627\u0631\u062f\u0648'),
                  ('roman_ur', 'Roman Urdu'),
                ])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(option.$2),
                    trailing: Icon(
                      settings.language == option.$1
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: settings.language == option.$1
                          ? MyBotTheme.accent
                          : null,
                    ),
                    onTap: () => notifier.patch(
                      (current) => current.copyWith(language: option.$1),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Appearance',
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Dark mode'),
                  value: settings.darkMode,
                  onChanged: (value) => notifier.patch(
                    (current) => current.copyWith(darkMode: value),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Notifications'),
                  subtitle: const Text('Signal and approval alerts'),
                  value: settings.notifications,
                  onChanged: (value) => notifier.patch(
                    (current) => current.copyWith(notifications: value),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Safety level',
            subtitle: 'How much runs without asking you first.',
            child: Column(
              children: [
                for (final level in SafetyLevel.values)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      level.label.split(' \u2014 ').first,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      level.label.split(' \u2014 ').last,
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: Icon(
                      settings.safety == level
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: settings.safety == level ? MyBotTheme.accent : null,
                    ),
                    onTap: () => notifier.patch(
                      (current) => current.copyWith(safety: level),
                    ),
                  ),
                if (settings.safety == SafetyLevel.permissive)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Permissive still asks before anything irreversible. '
                      'MyBot never presses Buy or Sell.',
                      style: TextStyle(fontSize: 11, color: MyBotTheme.warn),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Backup',
            subtitle: 'Settings and routing as JSON. Keys are not included.',
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final config = await ref.read(aiConfigProvider.future);
                      final payload = {
                        'app': settings.toJson(),
                        'ai': config.toJson(),
                        'exported_at': DateTime.now().toIso8601String(),
                      };
                      await Clipboard.setData(
                        ClipboardData(text: payload.toString()),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Backup copied to the clipboard.'),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_all_outlined, size: 18),
                    label: const Text('Copy backup'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Data',
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Clear chat history'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await ref.read(repositoriesProvider).chat.clear();
                    await ref.read(chatControllerProvider.notifier).refresh();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Chat cleared.')),
                    );
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Clear logs'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await ref.read(repositoriesProvider).logs.clear();
                    ref.invalidate(logsProvider);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Logs cleared.')),
                    );
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show onboarding again'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => notifier.patch(
                    (current) => current.copyWith(onboarded: false),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              'MyBot 1.0.0 · single-device, sideloaded',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
