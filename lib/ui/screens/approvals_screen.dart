import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ApprovalsScreen extends ConsumerStatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  ConsumerState<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends ConsumerState<ApprovalsScreen> {
  /// Loaded once per decision, not once per rebuild: a future built inside
  /// build() re-fetches on every repaint.
  Future<List<ApprovalRequest>>? _history;

  @override
  void initState() {
    super.initState();
    _reloadHistory();
  }

  void _reloadHistory() {
    setState(() {
      _history = ref.read(repositoriesProvider).approvals.recent(limit: 15);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = ref.watch(pendingApprovalsProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          'Approvals',
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'Nothing sensitive runs without a tap here. Check the screenshot, '
          'then decide.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        pending.when(
          loading: () => const LinearProgressIndicator(minHeight: 2),
          error: (error, _) => Text('$error'),
          data: (items) {
            if (items.isEmpty) {
              return const EmptyState(
                icon: Icons.verified_user_outlined,
                title: 'Nothing waiting',
                body: 'When a plan reaches a step that could send, post, '
                    'delete or open an order screen, it lands here first.',
              );
            }
            return Column(
              children: [
                for (final request in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ApprovalTile(
                      request: request,
                      onApprove: () async {
                        await ref
                            .read(chatControllerProvider.notifier)
                            .decide(request, true);
                        ref.invalidate(pendingApprovalsProvider);
                        _reloadHistory();
                      },
                      onReject: () async {
                        await ref
                            .read(chatControllerProvider.notifier)
                            .decide(request, false);
                        ref.invalidate(pendingApprovalsProvider);
                        _reloadHistory();
                      },
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<ApprovalRequest>>(
          future: _history,
          builder: (context, snapshot) {
            final items = snapshot.data ?? const <ApprovalRequest>[];
            final resolved =
                items.where((item) => item.status != 'pending').toList();
            if (resolved.isEmpty) return const SizedBox.shrink();
            return SectionCard(
              title: 'History',
              child: Column(
                children: [
                  for (final item in resolved)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(item.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(relativeTime(item.createdAt)),
                      trailing: StatusPill(
                        label: item.status,
                        color: switch (item.status) {
                          'approved' => MyBotTheme.ok,
                          'rejected' => MyBotTheme.danger,
                          _ => MyBotTheme.accent,
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ApprovalTile extends StatelessWidget {
  const _ApprovalTile({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  final ApprovalRequest request;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = request.screenshotPath;
    final hasScreenshot = path != null && File(path).existsSync();

    return SectionCard(
      title: request.title,
      subtitle: request.kind.toUpperCase(),
      trailing: const StatusPill(
        label: 'PENDING',
        color: MyBotTheme.warn,
        icon: Icons.lock_clock,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(request.detail, style: theme.textTheme.bodySmall),
          if (hasScreenshot) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(path),
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => const SizedBox.shrink(),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => onApprove(),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Approve'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => onReject(),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Reject'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
