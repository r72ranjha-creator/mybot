import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/media_models.dart';
import '../../data/research_models.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/source_list.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<MediaFile> _attachments = [];
  bool _listening = false;
  bool _importing = false;

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

  Future<void> _send({String? override}) async {
    final text = override ?? _controller.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    final attachments = List<MediaFile>.from(_attachments);
    final projectId = ref.read(activeProjectProvider);
    _controller.clear();
    setState(_attachments.clear);
    await ref.read(chatControllerProvider.notifier).send(
          text,
          attachments: attachments,
          projectId: projectId,
        );
    _scrollToEnd();
    final report = ref.read(chatControllerProvider).report;
    final messages = ref.read(chatControllerProvider).messages;
    final reply = messages.isEmpty ? null : messages.last;
    if (reply != null && !reply.isUser) {
      final muted = ref.read(ttsProvider).muted;
      if (!muted) {
        await ref.read(ttsProvider).speak(reply.content);
      }
      if (report != null && report.isUncited) {
        // Nothing to speak; the UI already shows the badge.
      }
    }
  }

  Future<void> _pickPhoto({bool camera = false}) async {
    setState(() => _importing = true);
    try {
      final picker = ref.read(imagePickerProvider);
      final List<XFile> files;
      if (camera) {
        final shot = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1568,
          maxHeight: 1568,
          imageQuality: 82,
        );
        files = shot == null ? const [] : [shot];
      } else {
        files = await picker.pickMultiImage(
          maxWidth: 1568,
          maxHeight: 1568,
          imageQuality: 82,
        );
      }
      final pipeline = ref.read(mediaPipelineProvider);
      for (final file in files.take(6)) {
        final media = await pipeline.importPath(
          file.path,
          kind: MediaKind.photo,
          mime: 'image/jpeg',
        );
        if (mounted) setState(() => _attachments.add(media));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Photo nahi mili: $error')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _pickFiles() async {
    setState(() => _importing = true);
    try {
      const group = XTypeGroup(
        label: 'Documents',
        extensions: ['pdf', 'txt', 'md', 'csv', 'xlsx', 'xls'],
      );
      final files = await openFiles(acceptedTypeGroups: const [group]);
      final pipeline = ref.read(mediaPipelineProvider);
      for (final file in files.take(3)) {
        final media = await pipeline.importPath(
          file.path,
          kind: MediaKind.file,
          mime: file.name.split('.').last,
        );
        if (mounted) setState(() => _attachments.add(media));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('File nahi mili: $error')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _toggleVoice() async {
    final stt = ref.read(sttProvider);
    if (_listening) {
      await stt.stop();
      setState(() => _listening = false);
      return;
    }
    setState(() => _listening = true);
    final text = await stt.start(
      onPartial: (partial) {
        if (mounted) _controller.text = partial;
      },
      onError: (message) {
        if (!mounted) return;
        setState(() => _listening = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      },
    );
    if (!mounted) return;
    setState(() => _listening = false);
    if (text.isNotEmpty) {
      _controller.text = text;
      await _send();
    }
  }

  Future<void> _speakLast() async {
    final tts = ref.read(ttsProvider);
    if (tts.isSpeaking) {
      await tts.stop();
      return;
    }
    final messages = ref.read(chatControllerProvider).messages;
    final last = messages.lastWhere(
      (message) => !message.isUser,
      orElse: () => messages.isEmpty
          ? throw StateError('no reply yet')
          : messages.last,
    );
    await tts.speak(last.content);
    final warning = tts.warning;
    if (warning != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(warning)));
    }
  }

  Future<void> _chooseAttachmentSource() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photos (gallery)'),
              subtitle: const Text('Ek se chhe tasveerain'),
              onTap: () => Navigator.of(context).pop('gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Camera se photo'),
              onTap: () => Navigator.of(context).pop('camera'),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('File (PDF, CSV, Excel, TXT)'),
              onTap: () => Navigator.of(context).pop('file'),
            ),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'gallery':
        await _pickPhoto();
      case 'camera':
        await _pickPhoto(camera: true);
      case 'file':
        await _pickFiles();
    }
  }

  void _research(String mode) {
    final text = _controller.text.trim();
    final verb = switch (mode) {
      'deep' => 'Deep research kar ke sources ke sath batao',
      'think' => 'Soch kar jawab do',
      _ => 'Research kar ke sources ke sath batao',
    };
    final command = text.isEmpty ? '$verb ' : '$verb: $text';
    _send(override: command);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(chatControllerProvider);
    final muted = ref.watch(ttsProvider).muted;
    final project = ref.watch(activeProjectProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Text(
                'Chat',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              IconButton(
                tooltip: muted ? 'Awaz band hai' : 'Awaz on hai',
                onPressed: () async {
                  final tts = ref.read(ttsProvider);
                  final next = !tts.muted;
                  tts.setMuted(next);
                  await ref
                      .read(appSettingsProvider.notifier)
                      .patch((settings) => settings.copyWith(voiceMuted: next));
                  setState(() {});
                },
                icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
              ),
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
                  title: 'Likhein, bolein ya photo bhejein',
                  body: 'Roman Urdu, Urdu ya English. "WhatsApp kholo", '
                      '"is chart ka trend batao", "BTC ki latest news research karo".',
                )
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  itemCount: state.messages.length,
                  itemBuilder: (context, index) {
                    final message = state.messages[index];
                    final isLast = index == state.messages.length - 1;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Bubble(
                          isUser: message.isUser,
                          text: message.content,
                          time: message.createdAt,
                          attachmentCount: message.attachmentCount,
                          onSpeak: message.isUser ? null : _speakLast,
                        ),
                        if (isLast && state.report != null)
                          SourceList(report: state.report!),
                      ],
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
        if (_attachments.isNotEmpty || _listening || _importing)
          _PreviewStrip(
            attachments: _attachments,
            listening: _listening,
            importing: _importing,
            projectName: project,
            onRemove: (media) => setState(() => _attachments.remove(media)),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Attach',
                      onPressed: state.busy ? null : _chooseAttachmentSource,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                    _ResearchMenu(onSelected: _research),
                    const Spacer(),
                    if (project != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: ActionChip(
                          avatar: const Icon(Icons.folder_outlined, size: 16),
                          label: const Text('Project'),
                          onPressed: () => ref
                              .read(activeProjectProvider.notifier)
                              .state = null,
                        ),
                      ),
                  ],
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: _listening ? 'Ruk jao' : 'Awaz se bolein',
                      onPressed: state.busy ? null : _toggleVoice,
                      icon: Icon(
                        _listening ? Icons.mic : Icons.mic_none,
                        color: _listening ? MyBotTheme.danger : null,
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
                          hintText: 'Command ya sawal likhein…',
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      onPressed: state.busy ? null : _send,
                      icon: const Icon(Icons.arrow_upward),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ResearchMenu extends StatelessWidget {
  const _ResearchMenu({required this.onSelected});

  final void Function(String mode) onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Research',
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final mode in ResearchMode.values)
          PopupMenuItem(
            value: mode.id,
            child: Row(
              children: [
                Icon(
                  switch (mode) {
                    ResearchMode.quick => Icons.travel_explore,
                    ResearchMode.deep => Icons.science_outlined,
                    ResearchMode.think => Icons.psychology_outlined,
                  },
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(mode.label),
              ],
            ),
          ),
      ],
      icon: const Icon(Icons.travel_explore),
    );
  }
}

class _PreviewStrip extends StatelessWidget {
  const _PreviewStrip({
    required this.attachments,
    required this.listening,
    required this.importing,
    required this.projectName,
    required this.onRemove,
  });

  final List<MediaFile> attachments;
  final bool listening;
  final bool importing;
  final String? projectName;
  final void Function(MediaFile media) onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (listening)
            const Padding(
              padding: EdgeInsets.only(right: 8, top: 12),
              child: StatusPill(
                label: 'Sun raha hoon…',
                color: MyBotTheme.danger,
                icon: Icons.mic,
              ),
            ),
          if (importing)
            const Padding(
              padding: EdgeInsets.only(right: 8, top: 12),
              child: StatusPill(
                label: 'Import…',
                color: MyBotTheme.accent,
                icon: Icons.downloading,
              ),
            ),
          for (final media in attachments)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 8),
              child: InputChip(
                avatar: Icon(
                  switch (media.kind) {
                    MediaKind.photo => Icons.image_outlined,
                    MediaKind.screenshot => Icons.screenshot_outlined,
                    MediaKind.file => Icons.description_outlined,
                    MediaKind.video => Icons.videocam_outlined,
                    MediaKind.audio => Icons.mic_none,
                  },
                  size: 16,
                ),
                label: Text(
                  '${media.fileName.length > 14 ? '${media.fileName.substring(0, 14)}…' : media.fileName} · ${media.sizeLabel}',
                  style: theme.textTheme.labelSmall,
                ),
                onDeleted: () => onRemove(media),
              ),
            ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.isUser,
    required this.text,
    required this.time,
    required this.attachmentCount,
    this.onSpeak,
  });

  final bool isUser;
  final String text;
  final DateTime time;
  final int attachmentCount;
  final VoidCallback? onSpeak;

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
            if (attachmentCount > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.attach_file, size: 13),
                    const SizedBox(width: 3),
                    Text('$attachmentCount',
                        style: theme.textTheme.labelSmall),
                  ],
                ),
              ),
            SelectableText(text, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  relativeTime(time),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
                if (onSpeak != null) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: onSpeak,
                    child: Icon(
                      Icons.volume_up_outlined,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
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
