# MyBot — build plan

State as of the first hand-off: the app compiles, the unit tests pass, and the
release APK builds. Everything below is ordered by what unblocks the most.

## Phase 0 — done in this build

- Flutter app shell, 9 screens, dark/light theme, Riverpod state.
- SQLite schema for chat, plans, strategies, signals, watchlist, approvals,
  logs, app rules, settings, usage.
- Kotlin AccessibilityService: read tree, tap by text / by view-id / by point,
  set text, scroll, swipe, back/home/recents, screenshot (API 30+).
- Manager bot: command parser → planner → risk gate → step routing → merge,
  with per-step retries and a hard step cap.
- Approval flow: sensitive steps create a card; approve resumes the plan,
  reject cancels it cleanly.
- TradingView loop: open app → search symbol → set timeframe → screenshot →
  vision analysis against saved JSON rules → signal. Never touches Buy/Sell.
- GitHub Actions workflow that produces the `MyBot-APK` artifact.

## Phase 1 — make it feel finished (next)

1. **Token streaming in Chat.** Stream responses into the bubble instead of
   waiting for the whole answer. Provider-side SSE for OpenAI-compatible and
   Gemini; a simple `StreamedLlmClient` alongside the current one.
2. **On-device voice input.** `speech_to_text` with `ur_PK` / `en_US` locales,
   hold-to-talk on the mic button, same planner path after transcription.
3. **Signal notifications.** Local notification when a signal is written,
   tapping it opens the signal detail. Needs a small Kotlin notification
   channel and POST_NOTIFICATIONS runtime request (already declared).
4. **Screenshot fallback below API 30.** MediaProjection with a one-time
   consent dialog, used only when `takeScreenshot` is unavailable.

## Phase 2 — trust and durability

5. **Encrypted backup export/import.** Settings and routing JSON out, keys
   optionally wrapped with a user passphrase. Currently "Copy backup" is
   plaintext JSON without keys.
6. **Plan replay and undo.** Every mutating step already logs; add a
   best-effort undo for reversible steps (back navigation, re-open previous
   app) and a "replay this plan" button in Logs.
7. **Rate and cost guard.** A daily token budget per role, surfaced in Usage;
   refuse to start a plan that would obviously blow it.
8. **Screen-agent loop.** Today one screen step = one planned action. Add a
   bounded perceive→act→verify loop (max 6 turns) for goals that need more
   than one tap, using the existing `dumpTree` + `Prompt.screenAgentSystem`.

## Phase 3 — trading depth

9. **Strategy rule editor UI.** A structured form (trend filter, entry trigger,
   invalidation, risk box) that writes the same JSON, instead of raw JSON.
10. **Journal analytics.** Win/loss by strategy and timeframe from the signals
    table, with a "did the rules match" score the vision model already returns.
11. **Watchlist sweep.** Sequential analysis of the watchlist on a schedule
    (workmanager), each result still an approval, never an order.

## Phase 4 — hardening

12. Release signing with a real keystore in CI secrets + versioned artifacts.
13. Instrumentation test that drives a mocked accessibility bridge end to end.
14. Crash reporting that is opt-in and strips prompts by default.

## Known gaps to keep honest about

- No automated test touches the Kotlin bridge yet; it is verified by unit tests
  around the Dart side only.
- `flutter build apk` produces one universal APK (~50 MB). Split-per-ABI would
  cut that in half but complicates the single-artifact download the phone needs.
- Screenshot capture is synchronous inside the method channel; on slow devices
  a 4K screenshot can take a second or two.
