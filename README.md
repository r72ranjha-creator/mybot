# MyBot

A phone-only AI assistant for Android. You type or say what you want in
English, Urdu or Roman Urdu; a Manager bot turns it into a small JSON plan,
routes each step to a specialist bot, and merges the results into one answer.
Sensitive steps stop and wait for your tap.

Built with Flutter (UI + orchestration) and Kotlin (accessibility automation).
Ships as a single sideloadable APK produced by GitHub Actions.

## Get the APK onto your phone

1. Push this repository to GitHub.
2. Actions → **Build MyBot APK** → Run workflow (or just push to `main`).
3. Open the finished run → **Artifacts** → download **MyBot-APK**.
4. On the phone, unzip the downloaded artifact and tap `MyBot-APK.apk`.
   Android will warn that the app is from an unknown source — allow it for
   your browser/file manager once.

The release APK is signed with the debug keystore generated on the runner.
That is what makes sideloading work with no secrets in the repository. If you
later want Play Store signing, add a keystore to repository secrets and wire it
in `android/app/build.gradle.kts`.

Requires Android 8.0+ (API 26). Screenshots need Android 11+ (API 30); on older
phones everything works except chart screenshots, and the app says so instead
of failing silently.

## First run

1. **Accessibility** — Settings → Accessibility → *MyBot automation* → on.
   Without it MyBot can plan but cannot open apps or read the screen.
2. **A model key** — More → AI settings → paste at least one key
   (Gemini, OpenAI, Anthropic or OpenRouter). Keys are stored in the Android
   Keystore, never in SQLite, never in a log line.
3. **A strategy** — Trading → *Strategies* → add one. The rules are JSON; they
   are what the vision model judges the chart against.

## The safety model

Every plan step carries a risk level: `read_only`, `reversible`, `sensitive`,
`irreversible`. The safety level in Settings decides which of those need an
approval tap:

| Safety level | Asks before |
|---|---|
| Strict | anything that changes state |
| Balanced (default) | anything that leaves a trace: sending, posting, order screens |
| Permissive | irreversible steps only |

Three things are structural, not settings:

- The TradingView flow ends at a signal. MyBot opens the chart, screenshots it,
  reads it and tells you what it sees — it never taps **Buy** or **Sell**.
- Blocked apps are never opened by any plan.
- STOP BOT freezes the queue immediately, mid-plan.

## Architecture

```
lib/
  agent/
    manager_bot.dart     controller: parse -> plan -> gate -> route -> merge
    prompts.dart         every model instruction, in one reviewable file
    llm_client.dart      OpenAI / Gemini / Anthropic / OpenRouter + fallbacks
    trading_engine.dart  TradingView loop, ends at the signal
    ai_config.dart       providers, per-role models, fallback order
  data/                  SQLite schema, repositories, Keystore-backed keys
  platform/              typed wrapper over the Kotlin bridge
  state/                 Riverpod providers and the chat controller
  ui/screens/            Onboarding, Home, Chat, Trading, Approvals,
                         Apps, Logs, AI settings, Settings
android/app/src/main/kotlin/com/mybot/assistant/
  MyBotAccessibilityService.kt   read tree, tap, type, scroll, screenshot
  A11yController.kt              the one MethodChannel surface
```

The bots are roles, not processes. Each role has its own provider + model and
its own fallback chain, so the vision analyst can run on a strong multimodal
model while the parser runs on something cheap. If a provider fails or has no
key, the next one in the chain is tried; the run still completes on the
remaining providers.

## Build locally

```bash
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`.

## What is deliberately not built yet

See `PLAN.md`. Short version: on-device voice input, token streaming in chat,
a MediaProjection fallback for screenshots below API 30, real notifications on
signal, and encrypted backup export/restore.
