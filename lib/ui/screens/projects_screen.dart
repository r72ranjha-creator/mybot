import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../data/research_models.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

class ProjectsScreen extends ConsumerWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final projects = ref.watch(projectsProvider);
    final active = ref.watch(activeProjectProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        actions: [
          IconButton(
            onPressed: () => _create(context, ref),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: projects.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Projects load nahi hue',
          body: '$error',
        ),
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.folder_outlined,
              title: 'Koi project nahi',
              body: 'Project bana kar us ke andar chat, reports aur files '
                  'alag rakh sakte hain. Manager Bot us project ka context '
                  'istemal karega.',
              action: FilledButton.icon(
                onPressed: () => _create(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Naya project'),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: items.length,
            separatorBuilder: (_, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final project = items[index];
              return Card(
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  leading: Icon(
                    active == project.id ? Icons.folder_open : Icons.folder,
                    color: active == project.id ? MyBotTheme.accent : null,
                  ),
                  title: Text(
                    project.name,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    project.description.isEmpty
                        ? 'No description'
                        : project.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'chat') {
                        ref.read(activeProjectProvider.notifier).state =
                            project.id;
                        ref.read(selectedTabProvider.notifier).state = 1;
                        Navigator.of(context).pop();
                      } else if (value == 'edit') {
                        await _create(context, ref, existing: project);
                      } else if (value == 'reports') {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ResearchReportsScreen(projectId: project.id),
                          ),
                        );
                      } else if (value == 'delete') {
                        await ref
                            .read(repositoriesProvider)
                            .projects
                            .delete(project.id);
                        if (active == project.id) {
                          ref.read(activeProjectProvider.notifier).state = null;
                        }
                        ref.invalidate(projectsProvider);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'chat', child: Text('Open in chat')),
                      PopupMenuItem(
                        value: 'reports',
                        child: Text('Reports and sources'),
                      ),
                      PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit name and instructions'),
                      ),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                  onTap: () {
                    ref.read(activeProjectProvider.notifier).state = project.id;
                    ref.read(selectedTabProvider.notifier).state = 1;
                    Navigator.of(context).pop();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _create(
    BuildContext context,
    WidgetRef ref, {
    Project? existing,
  }) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final description = TextEditingController(text: existing?.description ?? '');
    final instructions =
        TextEditingController(text: existing?.instructions ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Naya project' : 'Project edit'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Naam'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: description,
                decoration: const InputDecoration(labelText: 'Tafseel'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: instructions,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Instructions (Manager Bot inhe follow karega)',
                  hintText: 'Har jawab mein sources dein. Short rakhein.',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final trimmedName = name.text.trim();
    final trimmedDescription = description.text.trim();
    final trimmedInstructions = instructions.text.trim();
    name.dispose();
    description.dispose();
    instructions.dispose();
    if (saved != true || trimmedName.isEmpty) return;

    await ref.read(repositoriesProvider).projects.save(
          Project(
            id: existing?.id ?? const Uuid().v4(),
            name: trimmedName,
            description: trimmedDescription,
            instructions: trimmedInstructions,
            createdAt: existing?.createdAt ?? DateTime.now(),
          ),
        );
    ref.invalidate(projectsProvider);
  }
}

/// Report list for one project (or for everything when projectId is null).
class ResearchReportsScreen extends ConsumerWidget {
  const ResearchReportsScreen({super.key, this.projectId});

  final String? projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final reports = ref.watch(projectReportsProvider(projectId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Research'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: reports.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.error_outline,
          title: 'Reports load nahi hui',
          body: '$error',
        ),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.travel_explore,
              title: 'Koi research report nahi',
              body: 'Chat mein sawal likh kar Research ya Deep Research dabayein. '
                  'Har report sources ke sath save hoti hai.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            itemCount: items.length,
            separatorBuilder: (_, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final report = items[index];
              return Card(
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  title: Text(
                    report.question,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${report.mode.label} · '
                      '${relativeTime(report.createdAt)} · ${report.status}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReportViewScreen(reportId: report.id),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ReportViewScreen extends ConsumerStatefulWidget {
  const ReportViewScreen({super.key, required this.reportId});

  final String reportId;

  @override
  ConsumerState<ReportViewScreen> createState() => _ReportViewScreenState();
}

class _ReportViewScreenState extends ConsumerState<ReportViewScreen> {
  late Future<ResearchReport?> _report;

  @override
  void initState() {
    super.initState();
    _report = ref.read(repositoriesProvider).research.byId(widget.reportId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report'),
        actions: [
          FutureBuilder<ResearchReport?>(
            future: _report,
            builder: (context, snapshot) {
              final report = snapshot.data;
              if (report == null) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Copy report',
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: report.bodyMarkdown),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Report copied.')),
                  );
                },
                icon: const Icon(Icons.copy_all_outlined),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<ResearchReport?>(
        future: _report,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final report = snapshot.data;
          if (report == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'Report nahi mili',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Text(
                report.question,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '${report.mode.label} · '
                '${report.createdAt.toIso8601String().split('T').first}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const SizedBox(height: 16),
              SelectableText(report.bodyMarkdown),
            ],
          );
        },
      ),
    );
  }
}
