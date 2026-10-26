enum SourceTrust { high, medium, low }

extension SourceTrustX on SourceTrust {
  String get id => name;

  String get label => switch (this) {
        SourceTrust.high => 'High',
        SourceTrust.medium => 'Medium',
        SourceTrust.low => 'Low',
      };

  int get weight => switch (this) {
        SourceTrust.high => 3,
        SourceTrust.medium => 2,
        SourceTrust.low => 1,
      };

  static SourceTrust parse(String? value) => SourceTrust.values.firstWhere(
        (trust) => trust.name == value,
        orElse: () => SourceTrust.low,
      );
}

enum ResearchMode { quick, deep, think }

extension ResearchModeX on ResearchMode {
  String get id => name;

  String get label => switch (this) {
        ResearchMode.quick => 'Research',
        ResearchMode.deep => 'Deep Research',
        ResearchMode.think => 'Think Deeply',
      };

  static ResearchMode parse(String? value) => ResearchMode.values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => ResearchMode.quick,
      );
}

class Project {
  Project({
    required this.id,
    required this.name,
    required this.createdAt,
    this.description = '',
    this.instructions = '',
    this.icon = 'folder',
    this.archived = false,
  });

  final String id;
  final String name;
  final String description;

  /// Injected as system context whenever this project is active.
  final String instructions;
  final String icon;
  final bool archived;
  final DateTime createdAt;

  Project copyWith({
    String? name,
    String? description,
    String? instructions,
    bool? archived,
  }) =>
      Project(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        instructions: instructions ?? this.instructions,
        icon: icon,
        archived: archived ?? this.archived,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'instructions': instructions,
        'icon': icon,
        'archived': archived ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Project.fromMap(Map<String, Object?> map) => Project(
        id: map['id'] as String,
        name: map['name'] as String,
        description: (map['description'] as String?) ?? '',
        instructions: (map['instructions'] as String?) ?? '',
        icon: (map['icon'] as String?) ?? 'folder',
        archived: (map['archived'] as int? ?? 0) == 1,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );
}

class ResearchSource {
  ResearchSource({
    required this.id,
    required this.reportId,
    required this.url,
    required this.position,
    required this.trust,
    this.title = '',
    this.domain = '',
    this.publishedAt,
    this.snippet = '',
    this.trustReason = '',
    this.usedInAnswer = true,
  });

  final String id;
  final String reportId;
  final String url;
  final int position;
  final SourceTrust trust;
  final String title;
  final String domain;
  final DateTime? publishedAt;
  final String snippet;
  final String trustReason;
  final bool usedInAnswer;

  Map<String, Object?> toMap() => {
        'id': id,
        'report_id': reportId,
        'url': url,
        'title': title,
        'domain': domain,
        'published_at': publishedAt?.millisecondsSinceEpoch,
        'snippet': snippet,
        'trust': trust.id,
        'trust_reason': trustReason,
        'used_in_answer': usedInAnswer ? 1 : 0,
        'position': position,
      };

  factory ResearchSource.fromMap(Map<String, Object?> map) => ResearchSource(
        id: map['id'] as String,
        reportId: map['report_id'] as String,
        url: (map['url'] as String?) ?? '',
        title: (map['title'] as String?) ?? '',
        domain: (map['domain'] as String?) ?? '',
        publishedAt: map['published_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(map['published_at'] as int),
        snippet: (map['snippet'] as String?) ?? '',
        trust: SourceTrustX.parse(map['trust'] as String?),
        trustReason: (map['trust_reason'] as String?) ?? '',
        usedInAnswer: (map['used_in_answer'] as int? ?? 1) == 1,
        position: (map['position'] as int?) ?? 0,
      );
}

class ResearchReport {
  ResearchReport({
    required this.id,
    required this.question,
    required this.mode,
    required this.createdAt,
    this.projectId,
    this.parentId,
    this.summary = '',
    this.bodyMarkdown = '',
    this.status = 'done',
    this.sources = const [],
  });

  final String id;
  final String question;
  final ResearchMode mode;
  final DateTime createdAt;
  final String? projectId;

  /// Follow-up chain: set when this report answers a question about a parent.
  final String? parentId;
  final String summary;
  final String bodyMarkdown;
  final String status;
  final List<ResearchSource> sources;

  bool get isUncited => sources.isEmpty;

  ResearchReport withSources(List<ResearchSource> list) => ResearchReport(
        id: id,
        question: question,
        mode: mode,
        createdAt: createdAt,
        projectId: projectId,
        parentId: parentId,
        summary: summary,
        bodyMarkdown: bodyMarkdown,
        status: status,
        sources: list,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'project_id': projectId,
        'parent_id': parentId,
        'question': question,
        'mode': mode.id,
        'summary': summary,
        'body_md': bodyMarkdown,
        'status': status,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory ResearchReport.fromMap(
    Map<String, Object?> map, {
    List<ResearchSource> sources = const [],
  }) =>
      ResearchReport(
        id: map['id'] as String,
        projectId: map['project_id'] as String?,
        parentId: map['parent_id'] as String?,
        question: (map['question'] as String?) ?? '',
        mode: ResearchModeX.parse(map['mode'] as String?),
        summary: (map['summary'] as String?) ?? '',
        bodyMarkdown: (map['body_md'] as String?) ?? '',
        status: (map['status'] as String?) ?? 'done',
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        sources: sources,
      );
}

class SavedLink {
  SavedLink({
    required this.id,
    required this.url,
    required this.createdAt,
    this.title = '',
    this.note = '',
    this.projectId,
  });

  final String id;
  final String url;
  final String title;
  final String note;
  final String? projectId;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'url': url,
        'title': title,
        'note': note,
        'project_id': projectId,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory SavedLink.fromMap(Map<String, Object?> map) => SavedLink(
        id: map['id'] as String,
        url: map['url'] as String,
        title: (map['title'] as String?) ?? '',
        note: (map['note'] as String?) ?? '',
        projectId: map['project_id'] as String?,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );
}

class UserNote {
  UserNote({
    required this.id,
    required this.body,
    required this.createdAt,
    this.title = '',
    this.projectId,
    this.tags = '',
  });

  final String id;
  final String title;
  final String body;
  final String? projectId;
  final String tags;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'body': body,
        'project_id': projectId,
        'tags': tags,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory UserNote.fromMap(Map<String, Object?> map) => UserNote(
        id: map['id'] as String,
        title: (map['title'] as String?) ?? '',
        body: map['body'] as String,
        projectId: map['project_id'] as String?,
        tags: (map['tags'] as String?) ?? '',
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      );
}
