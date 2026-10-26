import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import '../../data/research_models.dart';
import 'search_client.dart';

/// Scores a domain the way a careful reader would: official and primary sources
/// first, major outlets next, content farms and unsourced forums last.
class TrustFilter {
  TrustFilter({Map<String, SourceTrust> pinned = const {}}) : _pinned = pinned;

  final Map<String, SourceTrust> _pinned;

  static const _high = {
    'reuters.com',
    'apnews.com',
    'bbc.com',
    'bbc.co.uk',
    'bloomberg.com',
    'ft.com',
    'wsj.com',
    'cnbc.com',
    'sec.gov',
    'federalreserve.gov',
    'ecb.europa.eu',
    'imf.org',
    'worldbank.org',
    'who.int',
    'nature.com',
    'science.org',
    'arxiv.org',
    'ieee.org',
    'acm.org',
    'github.com',
    'ethereum.org',
    'bitcoin.org',
    'binance.com',
    'coinbase.com',
    'kraken.com',
    'tradingview.com',
  };

  static const _medium = {
    'coindesk.com',
    'cointelegraph.com',
    'theblock.co',
    'decrypt.co',
    'techcrunch.com',
    'theverge.com',
    'wired.com',
    'forbes.com',
    'investopedia.com',
    'wikipedia.org',
    'medium.com',
  };

  static const _low = {
    'facebook.com',
    'instagram.com',
    'pinterest.com',
    'quora.com',
    'answers.yahoo.com',
    'bitcointalk.org',
    'blogspot.com',
    'wordpress.com',
    'tumblr.com',
  };

  String domainOf(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceFirst('www.', '').toLowerCase();
    } catch (_) {
      return '';
    }
  }

  ({SourceTrust trust, String reason}) rate(SearchHit hit) {
    final domain = domainOf(hit.url);
    if (domain.isEmpty) {
      return (trust: SourceTrust.low, reason: 'link theek nahi');
    }
    final pinned = _pinned[domain];
    if (pinned != null) {
      return (trust: pinned, reason: 'aap ne ye domain set kiya hai');
    }
    if (domain.endsWith('.gov') || domain.endsWith('.edu') || domain.endsWith('.mil')) {
      return (trust: SourceTrust.high, reason: 'sarkari / taleemi domain');
    }
    if (_high.any((known) => domain == known || domain.endsWith('.$known'))) {
      return (trust: SourceTrust.high, reason: 'known primary source');
    }
    if (_medium.any((known) => domain == known || domain.endsWith('.$known'))) {
      return (trust: SourceTrust.medium, reason: 'known news source');
    }
    if (_low.any((known) => domain == known || domain.endsWith('.$known'))) {
      return (trust: SourceTrust.low, reason: 'user-generated content');
    }
    if (hit.publishedAt != null) {
      return (trust: SourceTrust.medium, reason: 'date maujood hai');
    }
    return (trust: SourceTrust.low, reason: 'ajnabi domain, tareekh nahi');
  }

  /// Drops duplicates (same URL, or near-identical titles) and returns sources
  /// ordered High → Medium → Low, so the synthesis prompt sees the best first.
  List<SearchHit> rank(List<SearchHit> hits) {
    final seenUrls = <String>{};
    final seenTitles = <String>[];
    final kept = <SearchHit>[];

    for (final hit in hits) {
      final canonical = _canonical(hit.url);
      if (canonical.isEmpty || seenUrls.contains(canonical)) continue;
      final titleKey = _titleKey(hit.title);
      if (titleKey.isNotEmpty &&
          seenTitles.any((seen) => _similar(seen, titleKey))) {
        continue;
      }
      seenUrls.add(canonical);
      if (titleKey.isNotEmpty) seenTitles.add(titleKey);
      kept.add(hit);
    }

    kept.sort((a, b) {
      final byTrust = rate(b).trust.weight.compareTo(rate(a).trust.weight);
      if (byTrust != 0) return byTrust;
      return (b.score ?? 0).compareTo(a.score ?? 0);
    });
    return kept;
  }

  String _canonical(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.replaceFirst('www.', '').toLowerCase();
      final path = uri.path.replaceAll(RegExp(r'/+$'), '');
      return '$host$path${uri.hasQuery ? '?${uri.query}' : ''}';
    } catch (_) {
      return '';
    }
  }

  String _titleKey(String title) => title
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{Nd}\s]', unicode: true), '')
      .trim();

  bool _similar(String a, String b) {
    if (a == b) return true;
    final aWords = a.split(RegExp(r'\s+')).toSet();
    final bWords = b.split(RegExp(r'\s+')).toSet();
    if (aWords.isEmpty || bWords.isEmpty) return false;
    final overlap = aWords.intersection(bWords).length;
    return overlap / aWords.union(bWords).length > 0.8;
  }
}

/// Fetches a page and returns readable text. Only text leaves this class — no
/// cookies, no headers, no files.
class PageFetcher {
  PageFetcher({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ));

  final Dio _dio;
  static const _maxChars = 6000;

  Future<String?> fetch(String url) async {
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: {'User-Agent': 'MyBot/1.0 (personal research assistant)'},
          followRedirects: true,
          maxRedirects: 3,
        ),
      );
      final body = response.data;
      if (body == null || body.isEmpty) return null;
      return extractText(body);
    } catch (_) {
      return null;
    }
  }

  String? extractText(String htmlText) {
    try {
      final document = html_parser.parse(htmlText);
      for (final tag in const ['script', 'style', 'nav', 'footer', 'header', 'aside', 'form']) {
        for (final node in document.querySelectorAll(tag)) {
          node.remove();
        }
      }
      final title = document.querySelector('title')?.text.trim() ?? '';
      final main = document.querySelector('article') ??
          document.querySelector('main') ??
          document.body;
      final raw = main?.text ?? '';
      final cleaned = raw
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll(RegExp(r'\n{2,}'), '\n')
          .trim();
      if (cleaned.length < 200) return null;
      final text = cleaned.length > _maxChars
          ? '${cleaned.substring(0, _maxChars)}…'
          : cleaned;
      return title.isEmpty ? text : '$title\n\n$text';
    } catch (_) {
      return null;
    }
  }
}
