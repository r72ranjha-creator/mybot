import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Reads answers out loud. Deliberately dumb: split into sentences so long
/// answers start playing immediately, and stop dead when the app says stop.
class TtsService {
  TtsService({FlutterTts? engine}) : _tts = engine ?? FlutterTts();

  final FlutterTts _tts;
  bool _configured = false;
  bool _muted = false;
  bool _speaking = false;
  String? _warning;

  bool get muted => _muted;
  bool get isSpeaking => _speaking;

  /// Set when the phone has no voice for the requested language.
  String? get warning => _warning;

  void setMuted(bool value) {
    _muted = value;
    if (value) stop();
  }

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    try {
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(false);
      _configured = true;
    } catch (error) {
      debugPrint('tts init failed: $error');
    }
  }

  /// `languageCode` follows the reply language: ur / en / roman_ur.
  Future<void> speak(String text, {String languageCode = 'en'}) async {
    if (_muted) return;
    final clean = _plain(text);
    if (clean.isEmpty) return;
    await _ensureConfigured();

    _warning = null;
    if (languageCode == 'ur' || languageCode == 'roman_ur') {
      final applied = await _tryLanguage('ur-PK');
      if (!applied) {
        await _tryLanguage('hi-IN');
        _warning =
            'Urdu voice install nahi hai. Phone settings > Text-to-speech se '
            'Urdu voice add kar sakte hain.';
      }
    } else {
      await _tryLanguage('en-US');
    }

    _speaking = true;
    try {
      for (final sentence in _sentences(clean)) {
        await _tts.speak(sentence);
      }
    } catch (error) {
      debugPrint('tts speak failed: $error');
    } finally {
      _speaking = false;
    }
  }

  Future<bool> _tryLanguage(String tag) async {
    try {
      final result = await _tts.setLanguage(tag);
      return result == 1 || result == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    _speaking = false;
    try {
      await _tts.stop();
    } catch (_) {
      // Nothing to stop.
    }
  }

  /// Markdown and citations do not read well aloud.
  String _plain(String text) => text
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAll(RegExp(r'\[\[?\d+\]?\]'), '')
      .replaceAll(RegExp(r'[#*_>`]'), '')
      .replaceAll(RegExp(r'https?://\S+'), 'link')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  Iterable<String> _sentences(String text) sync* {
    final parts = text.split(RegExp(r'(?<=[.!?۔])\s+'));
    final buffer = StringBuffer();
    for (final part in parts) {
      if (buffer.length + part.length > 220 && buffer.isNotEmpty) {
        yield buffer.toString();
        buffer.clear();
      }
      buffer.write(part);
      buffer.write(' ');
    }
    if (buffer.toString().trim().isNotEmpty) yield buffer.toString().trim();
  }
}
