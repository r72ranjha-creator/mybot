import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'agent/ai_config.dart';
import 'state/providers.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

class MyBotApp extends ConsumerWidget {
  const MyBotApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider).valueOrNull ?? AppSettings();
    return MaterialApp(
      title: 'MyBot',
      debugShowCheckedModeBanner: false,
      theme: MyBotTheme.light(),
      darkTheme: MyBotTheme.dark(),
      themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.light,
      home: const RootGate(),
    );
  }
}

/// Onboarding once, then straight to work.
class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    if (settings.isLoading) {
      return const _Splash();
    }
    if (settings.hasError) {
      // A settings row that will not parse must not trap the user on a splash.
      return const HomeShell();
    }
    final value = settings.valueOrNull ?? AppSettings();
    return value.onboarded ? const HomeShell() : const OnboardingScreen();
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'MyBot',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 16),
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
