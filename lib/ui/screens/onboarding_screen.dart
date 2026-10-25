import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref
        .read(appSettingsProvider.notifier)
        .patch((current) => current.copyWith(onboarded: true));
  }

  void _next() {
    if (_page >= 2) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = ref.watch(serviceEnabledProvider).valueOrNull ?? false;
    final config = ref.watch(aiConfigProvider).valueOrNull;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _page = index),
                children: [
                  _Slide(
                    icon: Icons.bolt,
                    title: 'MyBot',
                    body: 'One command in Urdu, English or Roman Urdu. MyBot '
                        'plans it, does the safe parts, and asks you before '
                        'anything that leaves the phone.\n\n'
                        'It never places a trade. It never sends a message. '
                        'The last tap is always yours.',
                  ),
                  _Slide(
                    icon: Icons.accessibility_new,
                    title: 'Phone automation',
                    body: 'To open apps and read the screen, Android needs you '
                        'to switch on MyBot accessibility. You can turn it off '
                        'any time — MyBot simply stops being able to act.',
                    trailing: Column(
                      children: [
                        if (service)
                          const StatusPill(
                            label: 'Enabled',
                            color: MyBotTheme.ok,
                            icon: Icons.check_circle,
                          )
                        else
                          const StatusPill(
                            label: 'Not enabled yet',
                            color: MyBotTheme.warn,
                            icon: Icons.warning_amber_rounded,
                          ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await ref
                                .read(automationProvider)
                                .openAccessibilitySettings();
                            await Future<void>.delayed(
                              const Duration(seconds: 2),
                            );
                            ref.invalidate(serviceEnabledProvider);
                          },
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Open accessibility settings'),
                        ),
                      ],
                    ),
                  ),
                  _Slide(
                    icon: Icons.key,
                    title: 'One model key',
                    body: 'MyBot talks to a provider you choose and pay for '
                        'directly. Add at least one key — Gemini, OpenAI, '
                        'Anthropic or OpenRouter — and you can assign a '
                        'different model to each bot.',
                    trailing: Column(
                      children: [
                        Text(
                          config == null
                              ? ''
                              : '${config.providers.length} providers ready',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const _KeysShortcut(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.tune, size: 16),
                          label: const Text('Open AI settings later'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var index = 0; index < 3; index++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: index == _page ? 22 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: index == _page
                                ? theme.colorScheme.primary
                                : theme.dividerColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _next,
                      child: Text(_page >= 2 ? 'Start using MyBot' : 'Next'),
                    ),
                  ),
                  TextButton(
                    onPressed: _finish,
                    child: const Text('Skip'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({
    required this.icon,
    required this.title,
    required this.body,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, size: 28, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(body, style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
          if (trailing != null) ...[
            const SizedBox(height: 20),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _KeysShortcut extends StatelessWidget {
  const _KeysShortcut();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Open More > AI settings after onboarding to add your keys.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
