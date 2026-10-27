import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(logsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            tooltip: 'Clear logs',
            onPressed: () async {
              final confirmed = await confirmDestructive(
                context,
                title: 'Clear logs?',
                message: 'Activity log delete ho jayega.',
                action: 'Clear',
              );
              if (!confirmed) return;
              await ref.read(repositoriesProvider).logs.clear();
              ref.invalidate(logsProvider);
            },
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final option in const ['all', 'ok', 'failed', 'sensitive'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(option),
                      selected: _filter == option,
                      onSelected: (_) => setState(() => _filter = option),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: logs.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => EmptyState(
                icon: Icons.error_outline,
                title: 'Cannot read logs',
                body: '$error',
              ),
              data: (items) {
                final filtered = items.where((log) {
                  if (_filter == 'all') return true;
                  if (_filter == 'ok') return log.status == 'ok';
                  if (_filter == 'failed') return log.status == 'failed';
                  return log.status == 'sensitive' ||
                      log.status == 'no_trade' ||
                      log.status == 'long' ||
                      log.status == 'short';
                }).toList();
                if (filtered.isEmpty) {
                  return const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No log entries',
                    body: 'Every action MyBot takes is recorded here: app, '
                        'action, model, time and screenshot reference.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  itemCount: filtered.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final log = filtered[index];
                    return _LogTile(log: log);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log});

  final ActivityLog log;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (log.status) {
      'ok' => MyBotTheme.ok,
      'failed' => MyBotTheme.danger,
      _ => MyBotTheme.accent,
    };
    return Card(
      child: ListTile(
        // Three-line rows plus a trailing pill overflow on a narrow phone.
        isThreeLine: true,
        title: Text(
          '${log.app} · ${log.action}',
          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${log.model} · ${relativeTime(log.createdAt)}'
            '${log.detail.isEmpty ? '' : '\n${log.detail}'}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            StatusPill(label: log.status, color: color),
            if (log.screenshotPath != null)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Icon(Icons.image_outlined, size: 16),
              ),
          ],
        ),
        onTap: () => _open(context),
      ),
    );
  }

  void _open(BuildContext context) {
    final path = log.screenshotPath;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${log.app} · ${log.action}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Model: ${log.model}'),
            Text('Status: ${log.status}'),
            Text(
              'When: ${DateFormat('d MMM yyyy · HH:mm').format(log.createdAt.toLocal())}',
            ),
            if (log.detail.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(log.detail),
            ],
            if (path != null && File(path).existsSync()) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(path), height: 240, fit: BoxFit.contain),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
