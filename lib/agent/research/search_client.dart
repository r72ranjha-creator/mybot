import 'package:dio/dio.dart';

import '../../data/secure_store.dart';

class SearchHit {
  SearchHit({
    required this.title,
    required this.url,
    required this.snippet,
    this.publishedAt,
    this.score,
    this.rawContent,
    this.provider = '',
  });

  final String title;
  final String url;
  final String snippet;
  final DateTime? publishedAt;
  final double? score;
  final String? rawContent;
  final String provider;

  SearchHit copyWith({String? rawContent, String? snippet}) => SearchHit(
        title: title,
        url: url,
        snippet: snippet ?? this.snippet,
        publishedAt: publishedAt,
        score: score,
        rawContent: rawContent ?? this.rawContent,
        provider: provider,
      );
}

abstract class SearchProvider {
  SearchProvider({required this.id, required this.label, required this.dio});
  final String id;
  final String label;
  final Dio dio;

  Future<List<SearchHit>> search(String query, {int limit = 8});
}

class TavilyProvider extends SearchProvider {
  TavilyProvider({required super.dio, required this.apiKey})
      : super(id: 'tavily', label: 'Tavily');

  final String apiKey;

  @override
  Future<List<SearchHit>> search(String query, {int limit = 8}) async {
    final response = await dio.post<Map<String, Object?>>(
      'https://api.tavily.com/search',
      data: {
        'api_key': apiKey,
        'query': query,
        'max_results': limit,
        'search_depth': 'advanced',
        'include_raw_content': true,
        'include_answer': false,
      },
      options: Options(headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      }),
    );
    final results = (response.data?['results'] as List?) ?? const [];
    return results.whereType<Map>().map((raw) {
      return SearchHit(
        title: (raw['title'] as String?) ?? '',
        url: (raw['url'] as String?) ?? '',
        snippet: (raw['content'] as String?) ?? '',
        publishedAt: _parseDate(raw['published_date'] as String?),
        score: (raw['score'] as num?)?.toDouble(),
        rawContent: raw['raw_content'] as String?,
        provider: id,
      );
    }).where((hit) => hit.url.isNotEmpty).toList();
  }
}

class PerplexityProvider extends SearchProvider {
  PerplexityProvider({required super.dio, required this.apiKey})
      : super(id: 'perplexity', label: 'Perplexity');

  final String apiKey;

  @override
  Future<List<SearchHit>> search(String query, {int limit = 8}) async {
    final response = await dio.post<Map<String, Object?>>(
      'https://api.perplexity.ai/search',
      data: {
        'query': query,
        'max_results': limit,
      },
      options: Options(headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      }),
    );
    final results = (response.data?['results'] as List?) ?? const [];
    return results.whereType<Map>().map((raw) {
      return SearchHit(
        title: (raw['title'] as String?) ?? '',
        url: (raw['url'] as String?) ?? '',
        snippet: (raw['snippet'] as String?) ?? '',
        publishedAt: _parseDate(raw['date'] as String?),
        provider: id,
      );
    }).where((hit) => hit.url.isNotEmpty).toList();
  }
}

class BraveProvider extends SearchProvider {
  BraveProvider({required super.dio, required this.apiKey})
      : super(id: 'brave', label: 'Brave');

  final String apiKey;

  @override
  Future<List<SearchHit>> search(String query, {int limit = 8}) async {
    final response = await dio.get<Map<String, Object?>>(
      'https://api.search.brave.com/res/v1/web/search',
      queryParameters: {'q': query, 'count': limit},
      options: Options(headers: {
        'X-Subscription-Token': apiKey,
        'Accept': 'application/json',
      }),
    );
    final web = (response.data?['web'] as Map?) ?? const {};
    final results = (web['results'] as List?) ?? const [];
    return results.whereType<Map>().map((raw) {
      return SearchHit(
        title: (raw['title'] as String?) ?? '',
        url: (raw['url'] as String?) ?? '',
        snippet: (raw['description'] as String?) ?? '',
        publishedAt: _parseDate(raw['age'] as String?),
        provider: id,
      );
    }).where((hit) => hit.url.isNotEmpty).toList();
  }
}

class SerperProvider extends SearchProvider {
  SerperProvider({required super.dio, required this.apiKey})
      : super(id: 'serper', label: 'Serper');

  final String apiKey;

  @override
  Future<List<SearchHit>> search(String query, {int limit = 8}) async {
    final response = await dio.post<Map<String, Object?>>(
      'https://google.serper.dev/search',
      data: {'q': query, 'num': limit},
      options: Options(headers: {
        'X-API-KEY': apiKey,
        'Content-Type': 'application/json',
      }),
    );
    final organic = (response.data?['organic'] as List?) ?? const [];
    return organic.whereType<Map>().map((raw) {
      return SearchHit(
        title: (raw['title'] as String?) ?? '',
        url: (raw['link'] as String?) ?? '',
        snippet: (raw['snippet'] as String?) ?? '',
        publishedAt: _parseDate(raw['date'] as String?),
        provider: id,
      );
    }).where((hit) => hit.url.isNotEmpty).toList();
  }
}

/// Walks the configured provider order and returns the first that answers with
/// usable hits. Every provider that was skipped, and why, is reported to the UI —
/// silently degrading to "no results" would be a lie.
class SearchClient {
  SearchClient({
    required SecureStore secure,
    Dio? dio,
    this.order = const ['tavily', 'perplexity', 'brave', 'serper'],
  })  : _secure = secure,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 40),
            ));

  final SecureStore _secure;
  final Dio _dio;
  final List<String> order;

  final List<String> notes = [];
  String lastProvider = '';

  Future<List<SearchHit>> search(String query, {int limit = 8}) async {
    notes.clear();
    for (final id in order) {
      final key = await _secure.readKey('search_$id');
      if (key == null || key.trim().isEmpty) {
        notes.add('$id: key nahi hai');
        continue;
      }
      try {
        final provider = _build(id, key);
        final hits = await provider.search(query, limit: limit);
        if (hits.isNotEmpty) {
          lastProvider = provider.label;
          return hits;
        }
        notes.add('$id: koi result nahi');
      } catch (error) {
        notes.add('$id: ${_short(error)}');
      }
    }
    return const [];
  }

  Future<bool> hasAnyKey() async {
    for (final id in order) {
      final key = await _secure.readKey('search_$id');
      if (key != null && key.trim().isNotEmpty) return true;
    }
    return false;
  }

  Future<String?> test(String id, String key) async {
    try {
      final provider = _build(id, key);
      final hits = await provider.search('bitcoin', limit: 2);
      return hits.isEmpty ? 'connected, but no results' : 'ok · ${hits.length} hits';
    } catch (error) {
      return 'failed: ${_short(error)}';
    }
  }

  SearchProvider _build(String id, String key) => switch (id) {
        'tavily' => TavilyProvider(dio: _dio, apiKey: key),
        'perplexity' => PerplexityProvider(dio: _dio, apiKey: key),
        'brave' => BraveProvider(dio: _dio, apiKey: key),
        _ => SerperProvider(dio: _dio, apiKey: key),
      };

  String _short(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 401 || status == 403) return 'key rejected ($status)';
      if (status == 429) return 'rate limited';
      if (status != null) return 'HTTP $status';
      return error.type.name;
    }
    return '$error';
  }
}

DateTime? _parseDate(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw) ?? DateTime.tryParse(raw.replaceAll(' ', 'T'));
}
