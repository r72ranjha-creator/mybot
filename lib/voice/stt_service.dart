import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Thin wrapper over the platform recogniser.
///
/// The important design point: this returns **text**. The Manager Bot never
/// learns that a command arrived by voice — it goes through the same parser as
/// a typed command, so both paths can never drift apart.
class SttService {
  SttService({SpeechToText? engine}) : _speech = engine ?? SpeechToText();

  final SpeechToText _speech;
  bool _initialised = false;
  String? _localeId;

  bool get isListening => _speech.isListening;
  String? get localeId => _localeId;

  /// Picks the best locale the phone actually has, preferring Urdu then the
  /// closest acoustic model. Roman Urdu has no STT model anywhere, which is why
  /// the transcript is normalised afterwards by the command parser.
  Future<String> _chooseLocale() async {
    if (_localeId != null) return _localeId!;
    final locales = await _speech.locales();
    final ids = locales.map((locale) => locale.localeId).toList();
    for (final preferred in const ['ur_PK', 'ur_IN', 'hi_IN', 'en_PK', 'en_US']) {
      if (ids.contains(preferred)) {
        _localeId = preferred;
        return preferred;
      }
    }
    final urdu = ids.firstWhere(
      (id) => id.startsWith('ur') || id.startsWith('hi'),
      orElse: () => ids.isEmpty ? 'en_US' : ids.first,
    );
    _localeId = urdu;
    return urdu;
  }

  Future<bool> ensureReady() async {
    if (_initialised) return true;
    _initialised = await _speech.initialize(
      onError: (error) => debugPrint('stt error: ${error.errorMsg}'),
      onStatus: (status) => debugPrint('stt status: $status'),
    );
    return _initialised;
  }

  Future<String> start({
    void Function(String partial)? onPartial,
    void Function(String error)? onError,
  }) async {
    if (!await ensureReady()) {
      onError?.call(
        'Is phone par speech engine nahi hai. Google app install karein, '
        'ya type kar ke bhej dein.',
      );
      return '';
    }
    final locale = await _chooseLocale();
    final completer = _VoiceCompleter();

    await _speech.listen(
      localeId: locale,
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      cancelOnError: true,
      onResult: (SpeechRecognitionResult result) {
        final text = result.recognizedWords;
        onPartial?.call(text);
        if (result.finalResult) completer.finish(text);
      },
    );

    final text = await completer.future;
    return text.trim();
  }

  Future<void> stop() => _speech.stop();

  Future<void> cancel() => _speech.cancel();
}

class _VoiceCompleter {
  final _completer = Completer<String>();

  Future<String> get future => _completer.future;

  bool get isDone => _completer.isCompleted;

  void finish(String value) {
    if (_completer.isCompleted) return;
    _completer.complete(value);
  }
}
