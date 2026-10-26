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

The release APK is signed with `android/app/mybot-release.jks`, a fixed key
committed with the project. It exists so that consecutive builds share one
signing identity — otherwise every CI run would sign with a fresh debug key and
Android would refuse to install the update over the previous version, which
wipes your data each time.

That keystore protects nothing but this app's identity on your own phone. It is
a sideload convenience, **not** a secret, and it must never be reused for an app
you publish. For Play Store shipping, generate your own keystore and keep it in
repository secrets instead.

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

## What it can do

- **Voice** — mic in the composer (Urdu / English / Hindi recognition on the
  phone's engine), spoken replies, one-tap mute. Voice and typing converge on
  the same command parser, so a spoken command makes exactly the same plan.
- **Photos** — gallery (up to 6) or camera, preview and remove before sending,
  analysed by the vision model. Files are copied into app-private storage.
- **Files** — PDF, TXT, MD, CSV, XLSX. PDFs are sent to the model as documents
  (works for scans too); CSV/Excel are parsed on the phone so totals are real.
- **Research** — Tavily → Perplexity → Brave → Serper with automatic fallback,
  numbered citations, High/Medium/Low trust badges, and an explicit
  "Reliable source nahi mila" instead of a guess.
- **Deep Research** — 3–8 searches, deduped sources, a fixed report structure,
  saved to a project and searchable later.
- **Projects** — chats, reports and files grouped under custom instructions the
  Manager Bot follows.
- **Crypto mode** — news, official updates, GitHub activity, listings, unlocks,
  bullish/bearish factors, always sourced, never advice.
- **Internal search** — FTS5 over chats, reports, notes and file text, plus
  structured questions over the trading journal.
- **Order button** — off by default; when enabled, MyBot may press Buy/Sell
  only after a fresh screenshot check and a per-press approval. See below.

## The safety model

Every plan step carries a risk level: `read_only`, `reversible`, `sensitive`,
`irreversible`. The safety level in Settings decides which of those need an
approval tap:

| Safety level | Asks before |
|---|---|
| Strict | anything that changes state |
| Balanced (default) | anything that leaves a trace: sending, posting, order screens |
| Permissive | irreversible steps only |

The TradingView flow ends at a signal: MyBot opens the chart, screenshots it,
reads it and tells you what it sees.

**Pressing Buy/Sell** is a separate, opt-in capability, off by default
(`Settings → Trading`). When enabled it still requires, every single time:

1. a screenshot under 20 s old on the TradingView package,
2. a vision check that the visible button matches the side you asked for and the
   symbol on the order form,
3. your explicit approval on a card showing that screenshot.

Hard blocks: one press per plan, 60 s cooldown, never from a schedule or a
background task, never while the phone is locked. Each press is logged with a
post-press screenshot.

Blocked apps are never opened by any plan. STOP BOT freezes the queue
immediately, mid-plan.

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

See `PLAN.md`. Short version, in the order they will land: scheduled research,
PDF/Markdown export buttons, research follow-up control, then video (key frames
+ compression). Video and scheduled research both need native plugins, and no
build here has been run on a physical device yet — adding them blind is how you
break a working app.
