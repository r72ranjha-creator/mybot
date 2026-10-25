import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _sendingViaVoice = false;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _scrollToEnd();
    await ref.read(chatControllerProvider.notifier).send(text);
    _scrollToEnd();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(chatControllerProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                'Chat',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  await ref.read(repositoriesProvider).chat.clear();
                  await ref.read(chatControllerProvider.notifier).refresh();
                },
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Clear'),
              ),
            ],
          ),
        ),
        Expanded(
          child: state.messages.isEmpty
              ? const EmptyState(
                  icon: Icons.chat_bubble_outline,
                  title: 'Say it in English, Urdu or Roman Urdu',
                  body: 'Try: "WhatsApp kholo", "aaj ka BTC chart dekh kar '
                      'batao", or "screenshot le kar samjhao".',
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  itemCount: state.messages.length,
                  itemBuilder: (context, index) {
                    final message = state.messages[index];
                    return _Bubble(
                      isUser: message.isUser,
                      text: message.content,
                      time: message.createdAt,
                    );
                  },
                ),
        ),
        if (state.pendingApproval != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _ApprovalCard(
              title: state.pendingApproval!.title,
              detail: state.pendingApproval!.detail,
              onApprove: () => ref
                  .read(chatControllerProvider.notifier)
                  .decide(state.pendingApproval!, true),
              onReject: () => ref
                  .read(chatControllerProvider.notifier)
                  .decide(state.pendingApproval!, false),
            ),
          ),
        if (state.busy)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: BusyBar(label: state.status ?? 'Working…'),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Voice input',
                  onPressed: () {
                    // Voice capture is wired to the platform recogniser in the
                    // next build; the text path stays fully usable until then.
                    setState(() => _sendingViaVoice = !_sendingViaVoice);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Voice input arrives in the next build. Type for now '
                          '— the planner is identical either way.',
                        ),
                      ),
                    );
                  },
                  icon: Icon(
                    _sendingViaVoice ? Icons.mic : Icons.mic_none,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Command MyBot…',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: state.busy ? null : _send,
                  icon: const Icon(Icons.arrow_upward),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.isUser, required this.text, required this.time});

  final bool isUser;
  final String text;
  final DateTime time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primary.withValues(alpha: 0.16)
              : theme.cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isUser
                ? theme.colorScheme.primary.withValues(alpha: 0.3)
                : theme.dividerColor,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            SelectableText(text, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              relativeTime(time),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.title,
    required this.detail,
    required this.onApprove,
    required this.onReject,
  });

  final String title;
  final String detail;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shield_moon_outlined,
                    size: 18, color: MyBotTheme.warn),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(detail, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: onApprove,
                    child: const Text('Approve'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReject,
                    child: const Text('Reject'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
