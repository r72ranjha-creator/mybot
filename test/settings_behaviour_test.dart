import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mybot/agent/ai_config.dart';
import 'package:mybot/app.dart';
import 'package:mybot/data/db.dart';
import 'package:mybot/data/repositories.dart';
import 'package:mybot/state/providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// These tests mount the real widget tree against a real (in-memory) SQLite
/// database, so a setting that is written but never rendered — or rendered but
/// never written — fails here instead of on the phone.
/// `pumpAndSettle` never returns while a spinner is on screen, and the app
/// shows one while settings load, so pump a bounded number of frames instead.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    // The no-isolate factory keeps every query on the test's own isolate: the
    // widget binding runs in fake time, so a cross-isolate reply would never
    // arrive.
    databaseFactory = databaseFactoryFfiNoIsolate;
    // Every test file gets its own database file: `flutter test` runs files in
    // parallel and they would otherwise share one mybot.db on disk.
    await databaseFactory.setDatabasesPath(
      Directory.systemTemp.createTempSync('mybot_test').path,
    );
  });

  Future<void> seed(AppSettings settings) async {
    final repos = Repositories(AppDatabase.instance);
    await repos.settings.put(
      AppSettings.storageKey,
      encodeJson(settings.toJson()),
    );
  }

  setUp(() async {
    await AppDatabase.instance.close();
    // Seeded outside the widget test's fake-async zone: a real SQLite write
    // inside it would never complete.
    await seed(AppSettings(onboarded: true, darkMode: false));
  });

  test('patching a setting updates state immediately and persists', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(appSettingsProvider.future);

    final notifier = container.read(appSettingsProvider.notifier);
    await notifier.patch((s) => s.copyWith(darkMode: false));
    expect(container.read(appSettingsProvider).valueOrNull?.darkMode, isFalse);

    await notifier.patch((s) => s.copyWith(language: 'en'));
    final current = container.read(appSettingsProvider).valueOrNull!;
    expect(current.language, 'en');
    expect(current.darkMode, isFalse, reason: 'second patch must not reset the first');

    final stored = await Repositories(AppDatabase.instance)
        .settings
        .get(AppSettings.storageKey);
    expect(stored, contains('"darkMode":false'));
    expect(stored, contains('"language":"en"'));
  });

  test('a tap that lands before the row loads keeps the stored values', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await Repositories(AppDatabase.instance).settings.put(
      AppSettings.storageKey,
      encodeJson(
        AppSettings(onboarded: true, darkMode: false, language: 'ur').toJson(),
      ),
    );

    // The user taps a switch immediately, before the async read has finished.
    await container
        .read(appSettingsProvider.notifier)
        .patch((s) => s.copyWith(darkMode: true));

    final stored = await Repositories(AppDatabase.instance)
        .settings
        .get(AppSettings.storageKey);
    final saved = AppSettings.fromJson(
      (jsonDecodeMap(stored!)).cast<String, Object?>(),
    );
    expect(saved.darkMode, isTrue);
    expect(saved.onboarded, isTrue, reason: 'onboarding must not be reset');
    expect(saved.language, 'ur', reason: 'unrelated settings must survive');
  });

  testWidgets('dark mode switch repaints the whole app', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyBotApp()));
    await settle(tester);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.light);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await container
        .read(appSettingsProvider.notifier)
        .patch((s) => s.copyWith(darkMode: true));
    await settle(tester);

    final updated = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(updated.themeMode, ThemeMode.dark);
  });
}
