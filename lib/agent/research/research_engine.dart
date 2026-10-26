import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../data/repositories.dart';
import '../../data/research_models.dart';
import '../../data/secure_store.dart';
import '../ai_config.dart';
import '../llm_client.dart';
import '../prompts.dart';
import 'search_client.dart';
import 'trust_filter.dart';

class ResearchException implements Exception {
  ResearchException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Search-backed research with real citations.
///
/// The shape is fixed on purpose: plan → search → fetch → dedupe → synthesise
/// with numbered sources → verify every citation exists → save. A model that
/// invents `[7]` when only five sources exist cannot get past the verify step.
class ResearchEngine {
  ResearchEngine({
    required Repositories repositories,
    required LlmClient llm,
    required AiConfig config,
    required SecureStore secure,
    Dio? dio,
    List<String> order = const ['tavily', 'perplexity', 'brave', 'serper'],
  })  : _repos = repositories,
        _llm = llm,
        _config = config,
        _search = SearchClient(secure: secure, dio: dio, order: order),
        _fetcher = PageFetcher(dio: dio);

  final Repositories _repos;
  final LlmClient _llm;
  final AiConfig _config;
  final SearchClient _search;
  final PageFetcher _fetcher;
  static const _uuid = Uuid();

  List<String> get providerNotes => _search.notes;

  Future<bool> isConfigured() => _search.hasAnyKey();

  Future<ResearchReport> run({
    required String question,
    required ResearchMode mode,
    String? projectId,
    String? parentId,
    bool cryptoMode = false,
    String? projectInstructions,
    void Function(String stage)? onProgress,
  }) async {
    if (!await _search.hasAnyKey()) {
      throw ResearchException(
        'Research ke liye ek search key chahiye. More > AI settings > Search '
        'providers mein Tavily ya Brave ki key daal dein.',
      );
    }

    final reportId = _uuid.v4();
    final pinned = await _repos.research.ratings();
    final filter = TrustFilter(pinned: pinned);

    // 1 — plan the queries
    onProgress?.call('Research plan ban raha hai');
    final queries = await _planQueries(question, mode, cryptoMode, parentId);

    // 2 — search
    final allHits = <SearchHit>[];
    var usedProvider = '';
    for (final query in queries) {
      onProgress?.call('Search: $query');
      final hits = await _search.search(query, limit: mode == ResearchMode.deep ? 8 : 5);
      if (hits.isNotEmpty) usedProvider = _search.lastProvider;
      allHits.addAll(hits);
      await _repos.research.saveQuery(
        id: _uuid.v4(),
        reportId: reportId,
        query: query,
        provider: _search.lastProvider,
        hits: hits.length,
      );
    }

    final ranked = filter.rank(allHits);
    if (ranked.isEmpty) {
      final empty = _emptyReport(
        id: reportId,
        question: question,
        mode: mode,
        projectId: projectId,
        parentId: parentId,
      );
      await _persist(empty);
      return empty;
    }

    // 3 — read the best pages
    final wanted = switch (mode) {
      ResearchMode.quick => 4,
      ResearchMode.think => 5,
      ResearchMode.deep => 10,
    };
    onProgress?.call('Pages padhi ja rahi hain');
    final enriched = <SearchHit>[];
    for (final hit in ranked.take(wanted)) {
      if ((hit.rawContent ?? '').trim().length > 400) {
        enriched.add(hit.copyWith(
          rawContent: _clip(hit.rawContent!),
        ));
        continue;
      }
      final text = await _fetcher.fetch(hit.url);
      enriched.add(text == null ? hit : hit.copyWith(rawContent: text));
    }

    // 4 — build the numbered source list
    final sources = <ResearchSource>[];
    var position = 1;
    for (final hit in enriched) {
      final rating = filter.rate(hit);
      sources.add(ResearchSource(
        id: _uuid.v4(),
        reportId: reportId,
        url: hit.url,
        title: hit.title.isEmpty ? filter.domainOf(hit.url) : hit.title,
        domain: filter.domainOf(hit.url),
        publishedAt: hit.publishedAt,
        snippet: _clip(hit.snippet, 300),
        trust: rating.trust,
        trustReason: rating.reason,
        position: position++,
      ));
    }

    // 5 — synthesise
    onProgress?.call('Jawab likha ja raha hai');
    final synthesis = await _synthesise(
      question: question,
      mode: mode,
      sources: sources,
      documents: enriched,
      cryptoMode: cryptoMode,
      projectInstructions: projectInstructions,
      parentId: parentId,
    );

    final used = _citedPositions(synthesis);
    final finalSources = [
      for (final source in sources)
        ResearchSource(
          id: source.id,
          reportId: source.reportId,
          url: source.url,
          position: source.position,
          trust: source.trust,
          title: source.title,
          domain: source.domain,
          publishedAt: source.publishedAt,
          snippet: source.snippet,
          trustReason: source.trustReason,
          usedInAnswer: used.contains(source.position),
        ),
    ];

    final body = _composeBody(synthesis, finalSources, cryptoMode);
    final report = ResearchReport(
      id: reportId,
      question: question,
      mode: mode,
      createdAt: DateTime.now(),
      projectId: projectId,
      parentId: parentId,
      summary: _summarise(synthesis),
      bodyMarkdown: body,
      status: used.isEmpty ? 'uncited' : 'done',
      sources: finalSources,
    );

    await _persist(report);
    if (projectId != null) {
      await _repos.projects.link(projectId: projectId, reportId: report.id);
    }
    onProgress?.call('Sources: ${finalSources.length} · $usedProvider');
    return report;
  }

  Future<void> _persist(ResearchReport report) async {
    await _repos.research.saveReport(report);
    await _repos.research.saveSources(report.sources);
    await _repos.knowledge.index(
      kind: 'report',
      id: report.id,
      title: report.question,
      body: '${report.summary}\n${report.bodyMarkdown}',
    );
  }

  ResearchReport _emptyReport({
    required String id,
    required String question,
    required ResearchMode mode,
    String? projectId,
    String? parentId,
  }) =>
      ResearchReport(
        id: id,
        question: question,
        mode: mode,
        createdAt: DateTime.now(),
        projectId: projectId,
        parentId: parentId,
        summary: 'Reliable source nahi mila.',
        bodyMarkdown:
            '## Reliable source nahi mila.\n\n'
            'Search chalayi gayi, magar koi aisay source nahi mile jo bharosay '
            'ke qabil hon. Is sawal ka jawab main andazay se nahi dunga.',
        status: 'no_sources',
      );

  Future<List<String>> _planQueries(
    String question,
    ResearchMode mode,
    bool cryptoMode,
    String? parentId,
  ) async {
    final maxQueries = switch (mode) {
      ResearchMode.quick => 2,
      ResearchMode.think => 3,
      ResearchMode.deep => 8,
    };
    try {
      final response = await _llm.complete(
        config: _config,
        role: BotRole.researchPlanner,
        messages: [
          LlmMessage(
            role: 'system',
            text: Prompts.researchPlannerSystem(
              maxQueries: maxQueries,
              crypto: cryptoMode,
            ),
          ),
          LlmMessage(role: 'user', text: question),
        ],
        jsonMode: true,
        temperature: 0.2,
        maxTokens: 600,
      );
      final json = parseJsonObject(response.text);
      final raw = (json?['queries'] as List?) ?? const [];
      final queries = raw
          .whereType<String>()
          .map((query) => query.trim())
          .where((query) => query.length > 3)
          .take(maxQueries)
          .toList();
      if (queries.isNotEmpty) return queries;
    } catch (_) {
      // Planning is an optimisation; searching the raw question still works.
    }
    return [question];
  }

  Future<String> _synthesise({
    required String question,
    required ResearchMode mode,
    required List<ResearchSource> sources,
    required List<SearchHit> documents,
    required bool cryptoMode,
    required String? projectInstructions,
    required String? parentId,
  }) async {
    final buffer = StringBuffer();
    for (var index = 0; index < sources.length; index++) {
      final source = sources[index];
      final content = documents[index].rawContent ?? documents[index].snippet;
      buffer.writeln(
        '[${source.position}] ${source.title}\n'
        '${source.url}\n'
        '${source.domain} · ${source.trust.label} trust\n'
        '${source.publishedAt == null ? 'date: unknown' : 'date: ${source.publishedAt!.toIso8601String().split('T').first}'}\n'
        '${_clip(content, 2500)}\n',
      );
    }

    String? parentContext;
    if (parentId != null) {
      final parent = await _repos.research.byId(parentId);
      if (parent != null) {
        parentContext = 'Is sawal se pichla report (follow-up):\n'
            '${parent.summary}\n${_clip(parent.bodyMarkdown, 3000)}';
      }
    }

    final response = await _llm.complete(
      config: _config,
      role: BotRole.writer,
      messages: [
        LlmMessage(
          role: 'system',
          text: Prompts.researchWriterSystem(mode: mode, crypto: cryptoMode),
        ),
        LlmMessage(
          role: 'user',
          text: 'Sawal: $question\n\n'
              '${projectInstructions == null || projectInstructions.isEmpty ? '' : 'Project instructions: $projectInstructions\n\n'}'
              '${parentContext ?? ''}\n\n'
              'Sources (sirf inhi ko use karein, [n] se cite karein):\n$buffer',
        ),
      ],
      temperature: 0.25,
      maxTokens: mode == ResearchMode.deep ? 4000 : 1800,
    );
    return response.text;
  }

  /// Which sources the answer actually cited. Used to mark the rest "seen, not
  /// used" and to decide whether the answer deserves an uncited warning.
  Set<int> _citedPositions(String text) {
    final found = <int>{};
    for (final match in RegExp(r'\[(\d{1,2})\]').allMatches(text)) {
      final value = int.tryParse(match.group(1) ?? '');
      if (value != null) found.add(value);
    }
    return found;
  }

  String _composeBody(
    String synthesis,
    List<ResearchSource> sources,
    bool cryptoMode,
  ) {
    final buffer = StringBuffer(synthesis.trim());
    buffer.writeln('\n\n---\n\n### Sources\n');
    for (final source in sources) {
      final date = source.publishedAt == null
          ? 'date nahi'
          : source.publishedAt!.toIso8601String().split('T').first;
      buffer.writeln(
        '${source.position}. **${source.title}** — ${source.trust.label} trust\n'
        '   ${source.url}\n'
        '   ${source.domain} · $date · ${source.snippet}',
      );
    }
    if (cryptoMode) {
      buffer.writeln(
        '\n_Ye financial advice nahi hai. MyBot trade nahi karta._',
      );
    }
    return buffer.toString();
  }

  String _summarise(String synthesis) {
    final firstBlock = synthesis
        .split(RegExp(r'\n\s*\n'))
        .firstWhere((block) => block.trim().isNotEmpty, orElse: () => '');
    return _clip(firstBlock.replaceAll(RegExp(r'[#>*-]'), '').trim(), 300);
  }

  String _clip(String value, [int limit = 6000]) =>
      value.length <= limit ? value : '${value.substring(0, limit)}…';

  /// Re-runs the export path without touching the network.
  String exportMarkdown(ResearchReport report) {
    final date = report.createdAt.toIso8601String().split('T').first;
    return '# ${report.question}\n\n'
        '_${report.mode.label} · $date · MyBot_\n\n'
        '${report.bodyMarkdown}';
  }

  String exportPlain(ResearchReport report) {
    final text = report.bodyMarkdown
        .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
        .replaceAll('**', '')
        .replaceAll('---', '');
    return '${report.question}\n\n$text';
  }
}
