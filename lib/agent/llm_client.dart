import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../data/models.dart';
import '../data/repositories.dart';
import '../data/secure_store.dart';
import 'ai_config.dart';

class LlmMessage {
  LlmMessage({
    required this.role,
    required this.text,
    this.imageBase64,
    this.documentBase64,
    this.documentMime,
    this.documentName,
  });

  /// system | user | assistant
  final String role;
  final String text;

  /// PNG, base64. Used for screenshot analysis.
  final String? imageBase64;

  /// A whole document (PDF today), base64. All three providers accept these
  /// inline, which is why the app does not need an on-device PDF parser.
  final String? documentBase64;
  final String? documentMime;
  final String? documentName;

  bool get hasBinary => imageBase64 != null || documentBase64 != null;

  Map<String, Object?> toOpenAi() {
    if (!hasBinary) {
      return {'role': role, 'content': text};
    }
    final parts = <Map<String, Object?>>[
      {'type': 'text', 'text': text},
    ];
    if (imageBase64 != null) {
      parts.add({
        'type': 'image_url',
        'image_url': {'url': 'data:image/png;base64,$imageBase64'},
      });
    }
    if (documentBase64 != null) {
      parts.add({
        'type': 'file',
        'file': {
          'filename': documentName ?? 'document.pdf',
          'file_data':
              'data:${documentMime ?? 'application/pdf'};base64,$documentBase64',
        },
      });
    }
    return {'role': role, 'content': parts};
  }
}

class LlmResponse {
  LlmResponse({
    required this.text,
    required this.providerId,
    required this.model,
    required this.inputTokens,
    required this.outputTokens,
  });

  final String text;
  final String providerId;
  final String model;
  final int inputTokens;
  final int outputTokens;
}

class LlmException implements Exception {
  LlmException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks to whichever provider the role is configured for, and walks the
/// fallback chain until one of them gives a usable answer.
class LlmClient {
  LlmClient({
    required Repositories repositories,
    required SecureStore secure,
    Dio? dio,
  })  : _repos = repositories,
        _secure = secure,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 25),
                receiveTimeout: const Duration(seconds: 90),
                sendTimeout: const Duration(seconds: 30),
              ),
            );

  final Repositories _repos;
  final SecureStore _secure;
  final Dio _dio;
  static const _uuid = Uuid();

  Future<LlmResponse> complete({
    required AiConfig config,
    required String role,
    required List<LlmMessage> messages,
    bool jsonMode = false,
    double temperature = 0.3,
    int maxTokens = 1600,
  }) async {
    final roleConfig = config.role(role);
    if (roleConfig == null || !roleConfig.enabled) {
      throw LlmException('The $role model is disabled in AI settings.');
    }

    final attempts = <ModelRef>[
      ModelRef(providerId: roleConfig.providerId, model: roleConfig.model),
      ...roleConfig.fallbacks,
    ];

    final errors = <String>[];
    for (final attempt in attempts) {
      final provider = config.provider(attempt.providerId);
      if (provider == null || !provider.enabled) {
        errors.add('${attempt.providerId}: not enabled');
        continue;
      }
      final apiKey = await _secure.readKey(provider.id);
      if (apiKey == null || apiKey.trim().isEmpty) {
        errors.add('${provider.label}: no API key');
        continue;
      }
      try {
        final response = await _call(
          provider: provider,
          model: attempt.model,
          apiKey: apiKey,
          messages: messages,
          jsonMode: jsonMode,
          temperature: temperature,
          maxTokens: maxTokens,
        );
        await _repos.usage.add(
          UsageEntry(
            id: _uuid.v4(),
            role: role,
            provider: provider.id,
            model: attempt.model,
            inputTokens: response.inputTokens,
            outputTokens: response.outputTokens,
            createdAt: DateTime.now(),
          ),
        );
        return response;
      } on DioException catch (error) {
        errors.add('${provider.label}: ${_describe(error)}');
      } catch (error) {
        errors.add('${provider.label}: $error');
      }
    }

    throw LlmException(
      'No model answered. ${errors.isEmpty ? 'Add an API key in AI settings.' : errors.join(' · ')}',
    );
  }

  Future<LlmResponse> _call({
    required ProviderConfig provider,
    required String model,
    required String apiKey,
    required List<LlmMessage> messages,
    required bool jsonMode,
    required double temperature,
    required int maxTokens,
  }) {
    return switch (provider.kind) {
      ProviderKind.gemini => _callGemini(
          provider: provider,
          model: model,
          apiKey: apiKey,
          messages: messages,
          jsonMode: jsonMode,
          temperature: temperature,
          maxTokens: maxTokens,
        ),
      ProviderKind.anthropic => _callAnthropic(
          provider: provider,
          model: model,
          apiKey: apiKey,
          messages: messages,
          jsonMode: jsonMode,
          temperature: temperature,
          maxTokens: maxTokens,
        ),
      _ => _callOpenAiCompatible(
          provider: provider,
          model: model,
          apiKey: apiKey,
          messages: messages,
          jsonMode: jsonMode,
          temperature: temperature,
          maxTokens: maxTokens,
        ),
    };
  }

  Future<LlmResponse> _callOpenAiCompatible({
    required ProviderConfig provider,
    required String model,
    required String apiKey,
    required List<LlmMessage> messages,
    required bool jsonMode,
    required double temperature,
    required int maxTokens,
  }) async {
    final body = <String, Object?>{
      'model': model,
      'messages': messages.map((m) => m.toOpenAi()).toList(),
      'temperature': temperature,
      'max_tokens': maxTokens,
      if (jsonMode) 'response_format': {'type': 'json_object'},
    };
    final response = await _dio.post<Map<String, Object?>>(
      '${provider.baseUrl}/chat/completions',
      data: body,
      options: Options(headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      }),
    );
    final data = response.data ?? const {};
    final choices = (data['choices'] as List?) ?? const [];
    if (choices.isEmpty) throw LlmException('Empty response from ${provider.label}');
    final message = (choices.first as Map)['message'] as Map? ?? const {};
    final text = (message['content'] as String?) ?? '';
    final usage = (data['usage'] as Map?) ?? const {};
    return LlmResponse(
      text: text.trim(),
      providerId: provider.id,
      model: model,
      inputTokens: (usage['prompt_tokens'] as num?)?.toInt() ?? 0,
      outputTokens: (usage['completion_tokens'] as num?)?.toInt() ?? 0,
    );
  }

  Future<LlmResponse> _callAnthropic({
    required ProviderConfig provider,
    required String model,
    required String apiKey,
    required List<LlmMessage> messages,
    required bool jsonMode,
    required double temperature,
    required int maxTokens,
  }) async {
    final system = messages
        .where((m) => m.role == 'system')
        .map((m) => m.text)
        .join('\n\n');
    final contents = <Map<String, Object?>>[];
    for (final message in messages.where((m) => m.role != 'system')) {
      final blocks = <Map<String, Object?>>[
        {'type': 'text', 'text': message.text},
      ];
      if (message.imageBase64 != null) {
        blocks.add({
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': 'image/png',
            'data': message.imageBase64,
          },
        });
      }
      if (message.documentBase64 != null) {
        blocks.add({
          'type': 'document',
          'source': {
            'type': 'base64',
            'media_type': message.documentMime ?? 'application/pdf',
            'data': message.documentBase64,
          },
        });
      }
      contents.add({
        'role': message.role == 'assistant' ? 'assistant' : 'user',
        'content': blocks,
      });
    }
    final body = <String, Object?>{
      'model': model,
      'max_tokens': maxTokens,
      'temperature': temperature,
      'messages': contents,
      if (system.isNotEmpty) 'system': system,
    };
    final response = await _dio.post<Map<String, Object?>>(
      '${provider.baseUrl}/messages',
      data: body,
      options: Options(headers: {
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      }),
    );
    final data = response.data ?? const {};
    final blocks = (data['content'] as List?) ?? const [];
    final buffer = StringBuffer();
    for (final block in blocks) {
      final map = block as Map;
      if (map['type'] == 'text') buffer.write(map['text'] as String? ?? '');
    }
    final usage = (data['usage'] as Map?) ?? const {};
    return LlmResponse(
      text: buffer.toString().trim(),
      providerId: provider.id,
      model: model,
      inputTokens: (usage['input_tokens'] as num?)?.toInt() ?? 0,
      outputTokens: (usage['output_tokens'] as num?)?.toInt() ?? 0,
    );
  }

  Future<LlmResponse> _callGemini({
    required ProviderConfig provider,
    required String model,
    required String apiKey,
    required List<LlmMessage> messages,
    required bool jsonMode,
    required double temperature,
    required int maxTokens,
  }) async {
    final system = messages
        .where((m) => m.role == 'system')
        .map((m) => m.text)
        .join('\n\n');
    final contents = <Map<String, Object?>>[];
    for (final message in messages.where((m) => m.role != 'system')) {
      final parts = <Map<String, Object?>>[
        {'text': message.text},
      ];
      if (message.imageBase64 != null) {
        parts.add({
          'inline_data': {
            'mime_type': 'image/png',
            'data': message.imageBase64,
          },
        });
      }
      if (message.documentBase64 != null) {
        parts.add({
          'inline_data': {
            'mime_type': message.documentMime ?? 'application/pdf',
            'data': message.documentBase64,
          },
        });
      }
      contents.add({
        'role': message.role == 'assistant' ? 'model' : 'user',
        'parts': parts,
      });
    }
    final body = <String, Object?>{
      'contents': contents,
      if (system.isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': system},
          ],
        },
      'generationConfig': {
        'temperature': temperature,
        'maxOutputTokens': maxTokens,
        if (jsonMode) 'responseMimeType': 'application/json',
      },
    };
    final response = await _dio.post<Map<String, Object?>>(
      '${provider.baseUrl}/models/$model:generateContent',
      data: body,
      options: Options(headers: {
        'x-goog-api-key': apiKey,
        'Content-Type': 'application/json',
      }),
    );
    final data = response.data ?? const {};
    final candidates = (data['candidates'] as List?) ?? const [];
    if (candidates.isEmpty) {
      final blocked = (data['promptFeedback'] as Map?)?['blockReason'];
      throw LlmException(
        blocked == null
            ? 'Empty response from ${provider.label}'
            : '${provider.label} blocked the prompt ($blocked)',
      );
    }
    final content = (candidates.first as Map)['content'] as Map? ?? const {};
    final parts = (content['parts'] as List?) ?? const [];
    final buffer = StringBuffer();
    for (final part in parts) {
      buffer.write((part as Map)['text'] as String? ?? '');
    }
    final usage = (data['usageMetadata'] as Map?) ?? const {};
    return LlmResponse(
      text: buffer.toString().trim(),
      providerId: provider.id,
      model: model,
      inputTokens: (usage['promptTokenCount'] as num?)?.toInt() ?? 0,
      outputTokens: (usage['candidatesTokenCount'] as num?)?.toInt() ?? 0,
    );
  }

  String _describe(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) return 'key rejected ($status)';
    if (status == 429) return 'rate limited';
    if (status != null) return 'HTTP $status';
    return error.type.name;
  }

  /// Sends a tiny prompt to check a key works, without touching role config.
  Future<String> testProvider({
    required ProviderConfig provider,
    required String model,
    required String apiKey,
  }) async {
    final response = await _call(
      provider: provider,
      model: model,
      apiKey: apiKey,
      messages: [LlmMessage(role: 'user', text: 'Reply with the single word: ok')],
      jsonMode: false,
      temperature: 0,
      maxTokens: 8,
    );
    return response.text.isEmpty ? 'connected' : response.text;
  }
}

/// Models sometimes wrap JSON in prose or a fence. This digs the object out.
Map<String, Object?>? parseJsonObject(String raw) {
  final trimmed = raw.trim();
  final candidates = <String>[trimmed];
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(trimmed);
  if (fence != null) candidates.add(fence.group(1) ?? '');
  final start = trimmed.indexOf('{');
  final end = trimmed.lastIndexOf('}');
  if (start >= 0 && end > start) {
    candidates.add(trimmed.substring(start, end + 1));
  }
  for (final candidate in candidates) {
    if (candidate.trim().isEmpty) continue;
    try {
      final decoded = jsonDecode(candidate.trim());
      if (decoded is Map) return decoded.cast<String, Object?>();
    } catch (_) {
      continue;
    }
  }
  return null;
}

String describeRole(String role) => BotRole.labels[role] ?? role;
