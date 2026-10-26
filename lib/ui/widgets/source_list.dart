import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/research_models.dart';
import '../theme.dart';
import 'common.dart';

/// Renders the citations that belong to one answer.
///
/// Two things this widget refuses to do: hide a source that was used, and show
/// a Low-trust source without saying so.
class SourceList extends StatefulWidget {
  const SourceList({super.key, required this.report});

  final ResearchReport report;

  @override
  State<SourceList> createState() => _SourceListState();
}

class _SourceListState extends State<SourceList> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = widget.report;
    final used = report.sources.where((source) => source.usedInAnswer).toList();
    final seen = report.sources.where((source) => !source.usedInAnswer).toList();

    if (report.sources.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            const StatusPill(
              label: 'No source',
              color: MyBotTheme.danger,
              icon: Icons.report_gmailerrorred,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Reliable source nahi mila — jawab sirf andaza hai.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Row(
                  children: [
                    const Icon(Icons.link, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Sources · ${report.sources.length}',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    if (report.status == 'uncited')
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: StatusPill(
                          label: 'uncited',
                          color: MyBotTheme.warn,
                        ),
                      ),
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  ],
                ),
              ),
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final source in used) _SourceRow(source: source),
                    if (seen.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Dekhe gaye magar istemal nahi hue:',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      for (final source in seen)
                        _SourceRow(source: source, dimmed: true),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source, this.dimmed = false});

  final ResearchSource source;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = source.publishedAt == null
        ? 'date nahi'
        : source.publishedAt!.toIso8601String().split('T').first;

    return Opacity(
      opacity: dimmed ? 0.6 : 1,
      child: InkWell(
        onTap: () async {
          final uri = Uri.tryParse(source.url);
          if (uri == null) return;
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '${source.position}.',
                  style: theme.textTheme.labelSmall,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${source.domain} · $date',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (source.snippet.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          source.snippet,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(
                label: source.trust.label,
                color: switch (source.trust) {
                  SourceTrust.high => MyBotTheme.ok,
                  SourceTrust.medium => MyBotTheme.warn,
                  SourceTrust.low => MyBotTheme.danger,
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact one-line version used in project and report lists.
class SourceSummary extends StatelessWidget {
  const SourceSummary({super.key, required this.report});

  final ResearchReport report;

  @override
  Widget build(BuildContext context) {
    final high =
        report.sources.where((source) => source.trust == SourceTrust.high).length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.link, size: 12, color: Theme.of(context).hintColor),
        const SizedBox(width: 4),
        Text(
          '${report.sources.length} sources · $high high',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}
