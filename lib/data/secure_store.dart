import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// API keys never touch SQLite, never touch a log line and never leave the
/// device. They live in the Android Keystore via flutter_secure_storage.
class SecureStore {
  SecureStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;

  static String _keyFor(String providerId) => 'provider_key_$providerId';

  Future<String?> readKey(String providerId) =>
      _storage.read(key: _keyFor(providerId));

  Future<void> writeKey(String providerId, String value) =>
      _storage.write(key: _keyFor(providerId), value: value);

  Future<void> deleteKey(String providerId) =>
      _storage.delete(key: _keyFor(providerId));

  Future<bool> hasKey(String providerId) async {
    final value = await readKey(providerId);
    return value != null && value.trim().isNotEmpty;
  }

  /// Only used to mask the key in the settings UI.
  Future<String?> maskedKey(String providerId) async {
    final value = await readKey(providerId);
    if (value == null || value.isEmpty) return null;
    if (value.length <= 8) return '••••';
    return '${value.substring(0, 3)}••••${value.substring(value.length - 4)}';
  }

  Future<String?> exportBackup() async {
    final all = await _storage.readAll();
    return jsonEncode(all);
  }
}
