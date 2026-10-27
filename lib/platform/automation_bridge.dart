import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class NodeInfo {
  NodeInfo({
    required this.text,
    required this.desc,
    required this.viewId,
    required this.cls,
    required this.clickable,
    required this.editable,
    required this.scrollable,
    required this.x,
    required this.y,
  });

  final String text;
  final String desc;
  final String viewId;
  final String cls;
  final bool clickable;
  final bool editable;
  final bool scrollable;
  final int x;
  final int y;

  String get label => text.isNotEmpty ? text : desc;

  factory NodeInfo.fromMap(Map<String, Object?> map) => NodeInfo(
        text: (map['text'] as String?) ?? '',
        desc: (map['desc'] as String?) ?? '',
        viewId: (map['viewId'] as String?) ?? '',
        cls: (map['cls'] as String?) ?? '',
        clickable: (map['clickable'] as bool?) ?? false,
        editable: (map['editable'] as bool?) ?? false,
        scrollable: (map['scrollable'] as bool?) ?? false,
        x: (map['x'] as num?)?.toInt() ?? 0,
        y: (map['y'] as num?)?.toInt() ?? 0,
      );

  /// Compact form that goes into a model prompt — only what matters.
  Map<String, Object?> toPrompt() => {
        if (text.isNotEmpty) 'text': text,
        if (desc.isNotEmpty) 'desc': desc,
        if (viewId.isNotEmpty) 'viewId': viewId,
        if (clickable) 'clickable': true,
        if (editable) 'editable': true,
        if (scrollable) 'scrollable': true,
        'at': '$x,$y',
      };
}

class InstalledApp {
  InstalledApp({required this.package, required this.label});
  final String package;
  final String label;
}

class AutomationException implements Exception {
  AutomationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thin, typed wrapper over the Kotlin accessibility bridge. Nothing here
/// decides policy — the Manager Bot checks the allow/block list and the
/// approval gate before calling any mutating method.
class AutomationBridge {
  AutomationBridge({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('mybot/automation');

  final MethodChannel _channel;

  Future<bool> isServiceEnabled() async =>
      (await _invoke<bool>('isServiceEnabled')) ?? false;

  Future<bool> openAccessibilitySettings() async =>
      (await _invoke<bool>('openAccessibilitySettings')) ?? false;

  Future<bool> openApp(String package) async =>
      (await _invoke<bool>('openApp', {'package': package})) ?? false;

  Future<bool> openUrl(String url) async =>
      (await _invoke<bool>('openUrl', {'url': url})) ?? false;

  Future<List<InstalledApp>> installedApps() async {
    final raw = await _invoke<List<Object?>>('installedApps') ?? const [];
    return raw
        .whereType<Map>()
        .map((map) => InstalledApp(
              package: (map['package'] as String?) ?? '',
              label: (map['label'] as String?) ?? '',
            ))
        .where((app) => app.package.isNotEmpty)
        .toList();
  }

  Future<String> currentPackage() async =>
      (await _invoke<String>('currentPackage')) ?? '';

  Future<List<NodeInfo>> dumpTree() async {
    final raw = await _invoke<String>('dumpTree') ?? '[]';
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((map) => NodeInfo.fromMap(map.cast<String, Object?>()))
        .toList();
  }

  Future<bool> tapText(String text, {bool exact = false, int index = 0}) async =>
      (await _invoke<bool>('tapText', {
        'text': text,
        'exact': exact,
        'index': index,
      })) ??
      false;

  Future<bool> tapViewId(String viewId, {int index = 0}) async =>
      (await _invoke<bool>('tapViewId', {'viewId': viewId, 'index': index})) ??
      false;

  Future<bool> tapPoint(int x, int y) async =>
      (await _invoke<bool>('tapPoint', {'x': x, 'y': y})) ?? false;

  Future<bool> typeText(String text) async =>
      (await _invoke<bool>('typeText', {'text': text})) ?? false;

  Future<bool> setText(String hint, String text) async =>
      (await _invoke<bool>('setText', {'hint': hint, 'text': text})) ?? false;

  Future<bool> scroll(String direction) async =>
      (await _invoke<bool>('scroll', {'direction': direction})) ?? false;

  Future<bool> swipe(int x1, int y1, int x2, int y2,
          {int duration = 300}) async =>
      (await _invoke<bool>('swipe', {
        'x1': x1,
        'y1': y1,
        'x2': x2,
        'y2': y2,
        'duration': duration,
      })) ??
      false;

  Future<bool> back() async => (await _invoke<bool>('back')) ?? false;

  Future<bool> home() async => (await _invoke<bool>('home')) ?? false;

  /// Returns PNG bytes, or null when screenshots are unavailable (Android 10
  /// or older, or the accessibility service was revoked).
  Future<Uint8List?> screenshot() async {
    final base64Png = await _invoke<String>('screenshot');
    if (base64Png == null || base64Png.isEmpty) return null;
    return base64Decode(base64Png);
  }

  /// Screenshot saved to the app's own storage; the path is what we log.
  Future<String?> screenshotToFile({String prefix = 'screen'}) async {
    final bytes = await screenshot();
    if (bytes == null) return null;
    final dir = await getApplicationDocumentsDirectory();
    final shots = Directory(p.join(dir.path, 'shots'));
    if (!await shots.exists()) {
      await shots.create(recursive: true);
    }
    final file = File(
      p.join(shots.path, '${prefix}_${DateTime.now().millisecondsSinceEpoch}.png'),
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (error) {
      throw AutomationException(error.message ?? error.code);
    } on MissingPluginException {
      throw AutomationException('Automation is only available on Android.');
    }
  }
}
