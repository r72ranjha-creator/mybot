import 'dart:io';

import 'package:flutter/services.dart';

/// Local notifications, through a small channel.
///
/// Two moments are worth a notification and nothing else is: a new trade
/// signal, and an approval that is waiting for a tap. Both are things the user
/// only learns about if the app is not on screen.
class LocalNotifier {
  LocalNotifier({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('mybot/notify');

  final MethodChannel _channel;

  /// Asks for POST_NOTIFICATIONS on Android 13+. Returns whether it is granted
  /// right now; the system dialog answers later, which is why the setting stays
  /// on and the next notification simply works once the user allows it.
  Future<bool> ensurePermission() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('ensurePermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> show({
    required String title,
    required String body,
    int? id,
  }) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('show', {
            'title': title,
            'body': body,
            'id': id ?? DateTime.now().millisecondsSinceEpoch.remainder(100000),
          }) ??
          false;
    } catch (_) {
      // A notification that cannot be shown must never break the action.
      return false;
    }
  }
}
