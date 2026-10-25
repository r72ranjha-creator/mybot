import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../platform/automation_bridge.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

class AppsScreen extends ConsumerStatefulWidget {
  const AppsScreen({super.key});

  @override
  ConsumerState<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends ConsumerState<AppsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installed = ref.watch(installedAppsProvider);
    final rules = ref.watch(appRulesProvider).valueOrNull ?? const <AppRule>[];
    final blocked = {for (final rule in rules) rule.package: rule.blocked};
    final logs = ref.watch(logsProvider).valueOrNull ?? const <ActivityLog>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Apps'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          TextField(
            onChanged: (value) => setState(() => _query = value.toLowerCase()),
            decoration: const InputDecoration(
              hintText: 'Search installed apps',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Blocked apps are never opened by a plan. Everything else can be '
            'opened, but any step that changes something still asks you first.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          installed.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => EmptyState(
              icon: Icons.phonelink_erase,
              title: 'Cannot read the app list',
              body: '$error',
            ),
            data: (apps) {
              final filtered = apps
                  .where((app) =>
                      _query.isEmpty ||
                      app.label.toLowerCase().contains(_query) ||
                      app.package.toLowerCase().contains(_query))
                  .toList();
              if (filtered.isEmpty) {
                return const EmptyState(
                  icon: Icons.apps,
                  title: 'No apps matched',
                );
              }
              return SectionCard(
                title: '${filtered.length} apps',
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (final app in filtered)
                      SwitchListTile(
                        dense: true,
                        value: !(blocked[app.package] ?? false),
                        onChanged: (allowed) async {
                          final repos = ref.read(repositoriesProvider);
                          await repos.appRules.upsert(
                            AppRule(
                              package: app.package,
                              label: app.label.isNotEmpty
                                  ? app.label
                                  : app.package,
                            ),
                          );
                          await repos.appRules
                              .setBlocked(app.package, !allowed);
                          ref.invalidate(appRulesProvider);
                        },
                        title: Text(app.label),
                        subtitle: Text(
                          app.package,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        secondary: Icon(
                          blocked[app.package] ?? false
                              ? Icons.block
                              : Icons.check_circle_outline,
                          size: 20,
                          color: blocked[app.package] ?? false
                              ? MyBotTheme.danger
                              : MyBotTheme.ok,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Recent app activity',
            child: logs.isEmpty
                ? Text('No activity recorded yet.',
                    style: theme.textTheme.bodySmall)
                : Column(
                    children: [
                      for (final log in logs.take(12))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(
                            '${log.app} · ${log.action}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(relativeTime(log.createdAt)),
                          trailing: StatusPill(
                            label: log.status,
                            color: log.status == 'ok'
                                ? MyBotTheme.ok
                                : MyBotTheme.warn,
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Small helper so callers can show a snapshot of the device list.
Future<List<InstalledApp>> loadApps(WidgetRef ref) async {
  return ref.read(automationProvider).installedApps();
}
