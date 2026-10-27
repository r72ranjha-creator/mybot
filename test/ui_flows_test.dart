import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybot/agent/ai_config.dart';
import 'package:mybot/agent/llm_client.dart';
import 'package:mybot/app.dart';
import 'package:mybot/core/constants.dart';
import 'package:mybot/data/db.dart';
import 'package:mybot/data/repositories.dart';
import 'package:mybot/data/secure_store.dart';
import 'package:mybot/state/providers.dart';
import 'package:mybot/ui/screens/settings_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A stand-in for the network so these tests exercise the app, not a provider.
class _FakeLlm extends LlmClient {
  _FakeLlm(Repositories repos, SecureStore secure)
      : super(repositories: repos, secure: secure);

  @override
  Future<LlmResponse> complete({
    required AiConfig config,
    required String role,
    required List<LlmMessage> messages,
    bool jsonMode = false,
    double temperature = 0.3,
    int maxTokens = 1600,
  }) async {
    if (jsonMode) {
      return LlmResponse(
        text: '{"intent":"hello","language":"en","steps":[],"summary":""}',
        providerId: 'fake',
        model: 'fake',
        inputTokens: 1,
        outputTokens: 1,
      );
    }
    return LlmResponse(
      text: 'Hello from the fake model.',
      providerId: 'fake',
      model: 'fake',
      inputTokens: 1,
      outputTokens: 1,
    );
  }
}

Future<void> settle(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    // Every test file gets its own database file: `flutter test` runs files in
    // parallel and they would otherwise share one mybot.db on disk.
    await databaseFactory.setDatabasesPath(
      Directory.systemTemp.createTempSync('mybot_test').path,
    );
  });

  setUp(() async {
    await AppDatabase.instance.close();
    await Repositories(AppDatabase.instance).settings.put(
      AppSettings.storageKey,
      encodeJson(AppSettings(onboarded: true, darkMode: false).toJson()),
    );
  });

  Future<Widget> app() async => ProviderScope(
        overrides: [
          llmClientProvider.overrideWith(
            (ref) => _FakeLlm(
              ref.watch(repositoriesProvider),
              ref.watch(secureStoreProvider),
            ),
          ),
        ],
        child: const MyBotApp(),
      );

  /// Finds the bottom navigation destination with this label.
  Finder navItem(String label) => find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      );

  testWidgets('settings controls change the stored settings', (tester) async {
    await tester.pumpWidget(await app());
    await settle(tester);

    await tester.tap(navItem('More'));
    await settle(tester);
    await tester.tap(find.text('Settings'));
    await settle(tester);

    // Dark mode.
    await tester.tap(find.text('Dark mode'));
    await settle(tester);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
      reason: 'the theme must follow the switch',
    );

    // Notifications.
    await tester.tap(find.text('Notifications'));
    await settle(tester);

    // Language.
    await tester.tap(find.text('English'));
    await settle(tester);

    // Safety level. The row sits below the fold on a phone-sized screen.
    // The whole shell stays mounted behind this route, so the scrollable has
    // to be the one inside Settings, not the first in the tree.
    await tester.scrollUntilVisible(
      find.text('Permissive'),
      140,
      scrollable: find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(Scrollable),
      ),
    );
    // scrollUntilVisible stops as soon as the row is mounted, which can leave
    // it half under the fold; ensureVisible puts it fully on screen.
    await tester.ensureVisible(find.text('Permissive'));
    await settle(tester, frames: 6);
    await tester.tap(
      find.ancestor(
        of: find.text('Permissive'),
        matching: find.byType(ListTile),
      ),
    );
    await settle(tester);

    final stored = await Repositories(AppDatabase.instance)
        .settings
        .get(AppSettings.storageKey);
    final saved = AppSettings.fromJson(
      (jsonDecodeMap(stored!)).cast<String, Object?>(),
    );
    expect(saved.darkMode, isTrue);
    expect(saved.notifications, isFalse);
    expect(saved.language, 'en');
    expect(saved.safety, SafetyLevel.permissive);
  });

  testWidgets('Enter sends the typed command and shows it in the chat',
      (tester) async {
    await tester.pumpWidget(await app());
    await settle(tester);

    await tester.tap(navItem('Chat'));
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'Open WhatsApp');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await settle(tester);

    expect(find.text('Open WhatsApp'), findsWidgets,
        reason: 'the command must appear in the conversation');
  });

  testWidgets('the send button sends the typed command', (tester) async {
    await tester.pumpWidget(await app());
    await settle(tester);

    await tester.tap(navItem('Chat'));
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'Screenshot please');
    await tester.tap(find.byIcon(Icons.arrow_upward));
    await settle(tester);

    expect(find.text('Screenshot please'), findsWidgets);
  });
}
