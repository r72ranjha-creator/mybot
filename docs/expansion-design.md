# MyBot — Expansion Design (Phases 1–13)

Prepared for Raheem shah Raheem arif · 2026-10-26
Repo: `github.com/r72ranjha-creator/mybot` (private) · Design only — no code written yet.

---

## 0. TL;DR — the eight decisions that matter

| # | Decision | Why |
|---|---|---|
| 1 | Voice, media, research and projects are **additive modules**; `ManagerBot.handle(text)` keeps its exact signature | The existing pipeline is proven (13 tests, green CI); nothing new may rewrite it |
| 2 | Every new capability is a **new plan action**, routed by the same planner — not a second agent loop | One router, one approval gate, one log. Two control paths is how safety breaks |
| 3 | Search keys live in the **same Keystore store** as model keys, under a separate namespace | No second secret store to secure |
| 4 | Photos/videos/files go to **app-private storage**, never `Pictures/` | Android already sandboxes it; `allowBackup=false` is set |
| 5 | Media is **downscaled before upload** (1568 px, JPEG 80) and video is **key-frame only** | Token cost and phone bandwidth are the real limits, not model capability |
| 6 | Research answers carry **structured citations** (`research_sources`), rendered as a Sources block | An uncited research answer is a guess; the UI must make that visible |
| 7 | Database moves **v1 → v2, additive only**, `CREATE TABLE IF NOT EXISTS`, no column drops | Existing chat/plan/signal rows must survive the update |
| 8 | Buy/Sell tapping is **opt-in, per-press, always confirmed, never scheduled** | It is the only irreversible action in the app and it moves real money |

Effort, one engineer, honest: **~24–30 working days** for Phases 1–13. Phase 1+2 together: **4–5 days**.

---

## 1. Where the project stands today (the report you asked for)

### Shipped and verified

| Item | Evidence |
|---|---|
| Flutter app, 9 screens, Riverpod, SQLite | `flutter analyze` → 0 errors, 0 warnings (11 style infos) |
| Manager bot: parser → planner → risk gate → route → merge | `flutter test` → 13/13 pass |
| Kotlin accessibility service: tree, tap, type, scroll, swipe, screenshot | APK manifest inspected with `aapt2` |
| TradingView loop ending at the signal | `lib/agent/trading_engine.dart` |
| CI producing `MyBot-APK` | Runs 40247678305, 40248637838, 40249357066 all green |
| Stable signing so updates install over each other | Artifact cert SHA-256 `892232dd…`, matches local build |

### Not verified — and it matters

**Nothing has run on a physical Android device yet.** No emulator or phone is
available on my side. Every claim above is a build-time or static claim. Your
first install is the first real test, and the media/voice work below adds large
new surface area on top of an unproven base — which is why Phase 1 includes a
"first-run smoke test" as an explicit deliverable rather than an afterthought.

### Current structure

```
lib/
  agent/     manager_bot.dart  prompts.dart  llm_client.dart
             trading_engine.dart  ai_config.dart
  data/      db.dart  models.dart  repositories.dart  secure_store.dart
  platform/  automation_bridge.dart
  state/     providers.dart
  ui/        screens/ (9)  widgets/common.dart  theme.dart  shell.dart
android/app/src/main/kotlin/com/mybot/assistant/
  MainActivity.kt  A11yController.kt  MyBotAccessibilityService.kt
```

---

## 2. What must not break

These are contract tests, not wishes. Each gets a regression test before Phase 1
closes.

1. `ManagerBot.handle(String)` and `resolveApproval(...)` keep their signatures
   and current behaviour for the existing six plan actions.
2. The approval gate: `RiskLevel.needsApproval(SafetyLevel)` semantics unchanged
   for existing levels.
3. Blocked apps stay unopenable.
4. `AiConfig` JSON already on users' phones must load — new roles are **merged
   in**, never required.
5. Existing tables and rows survive the v1→v2 migration.
6. The CI artifact stays named `MyBot-APK` and keeps the same signing identity.

---

## 3. Target architecture

Three layers, and the arrow only points one way:

```
UI (screens/widgets)
  ↓ reads providers, calls controllers
STATE (Riverpod controllers: chat, media, research, projects)
  ↓
DOMAIN (ManagerBot, ResearchEngine, MediaPipeline, KnowledgeIndex)
  ↓ calls tools
TOOLS (LlmClient, SearchClient, AutomationBridge, FileExtractor, Tts, Stt)
  ↓
DATA (SQLite v2, Keystore, app-private files)
```

`ManagerBot` stays the single orchestrator. It gains a **tool registry**: a map
from plan action → async handler. Media, research and knowledge search are
handlers, not new loops. That is the whole trick that keeps routing in one place.

### Updated project structure

```
lib/
  agent/
    manager_bot.dart          # unchanged signature, extended dispatch table
    tool_registry.dart        # NEW action -> handler map, with risk + gating
    prompts.dart              # +research/citation/media prompts
    llm_client.dart           # + multi-image + structured-json retry helper
    ai_config.dart            # + role merge, + search provider config
    trading_engine.dart       # + tap_trade_button (gated, see §12)
    research/
      research_engine.dart    # NEW plan -> search -> fetch -> dedupe -> synth
      search_client.dart      # NEW provider abstraction + fallback
      providers/
        tavily.dart  perplexity.dart  brave.dart  serper.dart
      trust_filter.dart        # NEW domain/date/dup scoring
      report_renderer.dart     # NEW markdown/PDF export
    knowledge/
      knowledge_index.dart     # NEW FTS5 over chats, reports, files, notes
      internal_search.dart     # NEW query builder + result ranking
  media/
    media_pipeline.dart        # NEW pick/capture -> compress -> store -> describe
    image_tools.dart           # downscale, EXIF strip, thumbnails
    video_tools.dart           # probe, key-frame extract, compress
    file_extractor.dart        # pdf per-page text, csv, xlsx, txt/md
    media_store.dart           # app-private paths, delete, size accounting
  voice/
    stt_service.dart           # speech_to_text wrapper, locale negotiation
    tts_service.dart           # flutter_tts wrapper, mute, language pick
  data/
    db.dart                    # v2 schema + migration
    models.dart                # + MediaFile, Project, ResearchReport, ...
    repositories.dart          # + 10 new repositories
    secure_store.dart          # + search-key namespace
  state/
    providers.dart             # + media/research/project/voice providers
  ui/
    screens/                   # + projects, research_settings, scheduled_research
    widgets/chat_composer.dart # NEW: mic, speaker, attach, research buttons
    widgets/attachment_preview.dart
    widgets/source_card.dart   # NEW: citations with trust badge
    widgets/report_view.dart   # NEW: markdown report + export
android/app/src/main/kotlin/com/mybot/assistant/
    MediaProjectionService.kt  # NEW (Phase 3 optional capture)
    MyBotAccessibilityService.kt  # + screenshot region helper
    A11yController.kt          # + tapNodeInRegion for trade confirm
```

### New dependencies

| Package | Purpose | Note |
|---|---|---|
| `speech_to_text` | on-device STT | locale `ur_PK` may be absent on some phones — handled in §5 |
| `flutter_tts` | TTS | Urdu voice depends on the installed TTS engine |
| `image_picker` | gallery + camera, multi-select | |
| `file_picker` | pdf/txt/md/csv/xlsx | |
| `permission_handler` | ask mic/camera *when used* | |
| `video_thumbnail` | key frames via `MediaMetadataRetriever` | no ffmpeg needed |
| `video_compress` | shrink before upload | |
| `pdf_text` (fallback `pdfx`) | per-page PDF text | page numbers matter for citations |
| `excel`, `csv` | table extraction | |
| `html` | readable-text extraction from fetched pages | |
| `workmanager` | scheduled research | survives app kill |
| `flutter_local_notifications` | signal + scheduled report alerts | |
| `url_launcher` | open source links | |
| `pdf` + `printing` | export reports | |
| `flutter_markdown` | render reports | |

Versions are indicative; `pub` resolves against Flutter 3.47.8.

---

## 4. Database schema v2

Additive migration. `version: 2`, `onUpgrade` creates only what is missing.
Existing tables untouched; two nullable columns appended to `chat_messages`.

```sql
-- 4.1 media
CREATE TABLE IF NOT EXISTS media_files (
  id            TEXT PRIMARY KEY,
  kind          TEXT NOT NULL,          -- photo | video | screenshot | audio | file
  path          TEXT NOT NULL,          -- app-private absolute path
  mime          TEXT,
  bytes         INTEGER NOT NULL DEFAULT 0,
  width         INTEGER, height INTEGER,
  duration_ms   INTEGER,                -- video/audio
  sha256        TEXT,                   -- dedupe + integrity
  project_id    TEXT,
  extracted_text TEXT,                  -- OCR / PDF text, used for search
  created_at    INTEGER NOT NULL,
  deleted_at    INTEGER
);

CREATE TABLE IF NOT EXISTS chat_attachments (
  message_id  TEXT NOT NULL,
  media_id    TEXT NOT NULL,
  position    INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (message_id, media_id)
);

-- 4.2 projects
CREATE TABLE IF NOT EXISTS projects (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  description   TEXT,
  instructions  TEXT,                   -- injected as system context
  icon          TEXT,
  search_prefs  TEXT,                   -- JSON: providers, trust threshold
  archived      INTEGER NOT NULL DEFAULT 0,
  created_at    INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS project_files (
  project_id  TEXT NOT NULL,
  media_id    TEXT,
  report_id   TEXT,
  link_url    TEXT,
  added_at    INTEGER NOT NULL
);

-- 4.3 research
CREATE TABLE IF NOT EXISTS research_reports (
  id            TEXT PRIMARY KEY,
  project_id    TEXT,
  parent_id     TEXT,                   -- follow-up chain
  question      TEXT NOT NULL,
  mode          TEXT NOT NULL,          -- quick | deep | think
  summary       TEXT,
  body_md       TEXT,                   -- full structured report
  conclusions   TEXT,
  status        TEXT NOT NULL DEFAULT 'draft', -- draft|running|done|failed
  created_at    INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS research_queries (
  id          TEXT PRIMARY KEY,
  report_id   TEXT NOT NULL,
  query       TEXT NOT NULL,
  provider    TEXT,
  hits        INTEGER DEFAULT 0,
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS research_sources (
  id            TEXT PRIMARY KEY,
  report_id     TEXT NOT NULL,
  url           TEXT NOT NULL,
  title         TEXT,
  domain        TEXT,
  published_at  INTEGER,
  snippet       TEXT,
  trust         TEXT,                   -- high | medium | low
  trust_reason  TEXT,
  used_in_answer INTEGER NOT NULL DEFAULT 0,
  position      INTEGER                 -- citation number [1], [2]...
);

CREATE TABLE IF NOT EXISTS source_ratings (
  domain      TEXT PRIMARY KEY,
  trust       TEXT NOT NULL,
  notes       TEXT,
  updated_at  INTEGER NOT NULL
);

-- 4.4 saves + schedule + notes
CREATE TABLE IF NOT EXISTS saved_links (
  id          TEXT PRIMARY KEY,
  url         TEXT NOT NULL,
  title       TEXT,
  note        TEXT,
  project_id  TEXT,
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS scheduled_research (
  id           TEXT PRIMARY KEY,
  title        TEXT NOT NULL,
  question     TEXT NOT NULL,
  mode         TEXT NOT NULL DEFAULT 'quick',
  cadence      TEXT NOT NULL,           -- daily | weekdays | weekly | monthly
  time_of_day  TEXT NOT NULL,           -- "08:00" local
  timezone     TEXT NOT NULL DEFAULT 'Asia/Karachi',
  project_id   TEXT,
  enabled      INTEGER NOT NULL DEFAULT 1,
  last_run_at  INTEGER,
  next_run_at  INTEGER,
  created_at   INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS user_notes (
  id          TEXT PRIMARY KEY,
  title       TEXT,
  body        TEXT NOT NULL,
  project_id  TEXT,
  tags        TEXT,
  created_at  INTEGER NOT NULL
);

-- 4.5 internal search
CREATE VIRTUAL TABLE IF NOT EXISTS internal_fts USING fts5(
  source_kind,  -- chat | report | note | file | signal
  source_id UNINDEXED,
  title,
  body,
  tokenize = 'unicode61'
);
```

`chat_messages` gains `project_id TEXT` and `attachment_count INTEGER DEFAULT 0`.

**Migration rule**: `onUpgrade` runs inside one transaction, wrapped in
`IF NOT EXISTS`, and the app boots even if it throws — a migration failure must
degrade to read-only, never to a white screen. FTS rows are backfilled lazily
by a `KnowledgeIndex.reindex()` job so upgrade stays fast.

---

## 5. Voice design (Phase 1)

### Flow

```
[mic pressed] → permission (first time) → STT locale negotiate
   → partial results stream into the composer (user sees and can edit)
   → final transcript → CommandParser (existing role) normalises to
     {intent, language, entities}
   → ManagerBot.handle(text)              ← unchanged entry point
   → answer → TTS if speaker is on
```

Read that again: the voice path **converges on the existing text path at the
parser**. There is no second command pipeline, so a voice command and a typed
command are identical from there on — same plan, same gate, same logs.

### Locale negotiation

1. Ask the engine for `getLanguages` / `getLocales`.
2. Prefer, in order: `ur_PK` → `hi_IN` (closest acoustic model for Urdu speech)
   → `en_PK` → `en_US`.
3. Whatever is chosen is shown as a small chip ("Sun raha hoon: اردو") so the
   user is never guessing why recognition is poor.
4. Roman Urdu has no STT model. The transcript will arrive as Urdu script or
   anglicised text; the **parser already converts both** into the same task
   shape — this is why the existing parser is worth reusing instead of writing
   a new one.

### TTS

- `flutter_tts`, speak per sentence as the answer streams in, so long answers
  start playing immediately.
- Language follows the reply language; if no Urdu voice is installed, fall back
  to the default engine voice and show one inline notice
  ("Urdu voice install nahi hai — Settings > Text-to-speech se add karein").
- Mute/unmute is one persisted boolean (`settings.voice.muted`). Pressing the
  mic while muted unmutes; pressing speaker toggles per-message playback.
- Hard stop: any navigation away, or STOP BOT, calls `tts.stop()`.

### Failure modes, designed for

| Failure | Behaviour |
|---|---|
| No STT engine on the phone | Mic shows a one-line explanation + a link to install Google app; typing still works |
| Mic permission denied | Ask once, then explain what breaks without it; never nag |
| Silence / no speech | Cancel silently after 8 s, no error toast |
| Very long dictation | Cap at 60 s, keep what was captured |

---

## 6. Photo · video · screenshot · file (Phases 2–4)

### One pipeline, four entry points

```
pick/capture → MediaPipeline.import()
  1. copy into app-private media/ (never the public gallery)
  2. probe: size, dimensions, duration
  3. normalise: image → 1568 px long edge, JPEG 80; video → probe, maybe compress
  4. hash → dedupe against media_files.sha256
  5. store row, strip EXIF GPS
  6. attach to the message
→ send → ManagerBot receives media descriptors, not raw bytes
→ the step that needs eyes calls LlmClient with images
```

Media never enters `ManagerBot` as bytes; it enters as ids. That keeps the bot
logic unchanged and testable, and lets the UI re-render previews without
re-reading the file.

### Photos (Phase 2)

- Gallery multi-select (up to 6), camera capture, preview strip, remove before send.
- Preview shows the *compressed* version that will actually be uploaded — no
  surprises about quality after sending.
- Vision payload: up to 4 images per request; more than 4 → analysed in batches
  and summarised. Each image tagged `[photo 1]` in the prompt so the answer can
  say which one it refers to.
- Prompts: freestanding questions ("Is photo mein kya hai?"), chart questions
  (routed to the trading prompt with the saved strategy), receipt/document
  questions (extraction prompt returning key/value pairs).
- Deletion is a real delete: file unlinked, row marked `deleted_at`, attachment
  links removed; a "Storage" row in Settings shows the total bytes.

### Video (Phase 3)

No ffmpeg on device, and shipping it would add ~40 MB. So:

- Capture with `camera` at `maxDuration` from Settings (30 s / 1 min / 3 min).
- **Key frames**: `video_thumbnail` pulls N frames at even intervals
  (default 6; 1 frame per 5 s, capped at 8) plus one frame per detected scene
  cut if cheap. Each frame carries its timestamp.
- Prompt format: `[00:00] [00:15] [00:30] …` + "answer with timestamps where the
  important moments are". The model cites frame times; the UI taps to seek.
- Size guard: > 25 MB or > 3 min → warn before upload; offer compress
  (`video_compress`, 720 p / ~2 Mbps) which typically lands a 1-min clip under 8 MB.
- Audio is **not** transcribed in Phase 3 — that is a separate STT pass over the
  extracted audio track, deferred to Phase 3b. Say so in the UI rather than
  pretending the summary heard the speech.

### Screenshot (Phase 4)

- Upload from gallery (same pipeline), plus the existing in-app capture path.
- OCR: on-device text extraction where the ML Kit-free option is enough
  (accessibility tree if the screen is live; otherwise the vision model's text
  reading). Extracted text goes to `media_files.extracted_text` so it is
  searchable later.
- Every screenshot attached to a task is written to `activity_logs.screenshot_path`
  as today — logging behaviour does not change.

### Files (Phase 4)

| Type | Extraction | Citation |
|---|---|---|
| PDF | `pdf_text`, page by page | answer cites `[page 4]` |
| TXT/MD | direct | line/heading |
| CSV | `csv` → header + sample rows + aggregate stats | row range |
| XLSX | `excel` → sheet names, headers, row counts, first N rows | sheet name |
| Large file (> 2 MB text) | chunk + embed-free lexical top-K selection | chunk index |

Tables are extracted structurally (not as prose) so the analyst bot can
aggregate: "sum of the Amount column = 41,300".

---

## 7. Research (Phases 5, 6, 11, 12)

### Provider abstraction

```dart
abstract class SearchProvider {
  String get id;                 // tavily | perplexity | brave | serper
  bool get needsKey;
  Future<List<SearchHit>> search(String query, {int limit = 8});
}

class SearchHit {
  final String title, url, snippet;
  final DateTime? publishedAt;
  final double? score;
  final String? rawContent;      // only Tavily/Perplexity return this
}
```

`SearchClient.resolve(config)` walks the configured order and returns the first
provider that answers with ≥1 usable hit. Order default:
**Tavily → Perplexity → Brave → Serper**. A provider with no key is skipped
silently; the UI shows which one actually answered ("Sources: Tavily").

Keys: `SecureStore.writeKey('search_$id', key)` — same Keystore, separate
namespace, masked in AI Settings exactly like model keys, never logged.

### Citation model

Every hit that survives the trust filter becomes a `research_sources` row with a
stable position. The synthesis prompt is given the numbered list and must answer
with inline `[1]`, `[3]` markers. Post-processor:

- strips citations that do not map to a source row (no invented references),
- renumbers by first appearance,
- flags answers where **no** citation appears as `uncited: true`, and the UI
  shows that plainly.

### Cited answer UI

```
┌──────────────────────────────────────────────┐
│ BTC ka halal paisa…                          │
│ … summary … [1] … details … [2][3]           │
├──────────────────────────────────────────────┤
│ Sources                                      │
│ 1  Bitcoin spot ETF inflows hit record  🟢 High│
│    reuters.com · 12 Oct 2026 · one-liner     │
│ 2  Exchange reserves drop to 5-year low 🟡 Med│
│    coindesk.com · 11 Oct 2026 · one-liner    │
│ 3  Forum thread, unsigned        🔴 Low       │
│    bitcointalk.org · 2026 · shown, not trusted│
└──────────────────────────────────────────────┘
```

Rules the UI enforces: Low-trust sources are never the only support for a factual
claim (the renderer marks the claim as "weakly supported"); contradicting sources
render side by side under "Sources disagree"; when nothing passes the filter the
answer is exactly **"Reliable source nahi mila."** and no synthesis is attempted.

### Trust filter

| Signal | Weight |
|---|---|
| Domain in allowlist (gov, `.edu`, exchanges, protocol docs, Reuters/Bloomberg/AP, GitHub, official project domains) | +3 |
| Domain in denylist (content farms, known aggregators, unsourced forums) | −3 |
| Publish date present and < 18 months | +1 |
| Publish date missing | −1 |
| Duplicate content (URL canonical + 8-gram Jaccard > 0.8) | dropped |
| Title/snippet matches query entities | +1 |

Score → High ≥ 5, Medium 2–4, Low ≤ 1. `source_ratings` lets the user pin a
domain permanently ("always treat this as High"), which overrides the heuristic.

### Deep Research workflow

```
1  ResearchEngine.plan(question, project)
     → ManagerBot calls research_planner role
     → 3–8 sub-questions, each an independent query
2  For each sub-question: search, keep top 8 hits
3  Merge, canonicalise URLs, drop duplicates (Jaccard), drop Low unless the
   question is thin on sources
4  Fetch the best 8–12 pages (Tavily raw_content; else html → readable text,
   truncate to 6k chars each)
5  source_critic role: per source → trust, date, one-line summary, and
   "supports / contradicts / background" against each finding
6  Compare facts: findings backed by ≥2 independent High sources become
   "Key findings"; single-source findings are labelled as such
7  writer role produces the structured report (see §7.6)
8  Persist report + sources + queries; index into FTS
9  Offer: Save to Project · Export PDF/Markdown/text · Ask follow-up
```

Limits that keep it honest and cheap: ≤ 8 queries, ≤ 12 pages, ≤ 90k input
tokens, hard stop at 90 s with partial results saved as `failed` + what it got.

Report skeleton (fixed, so exports are predictable):
Executive summary → Key findings (each with citations) → Detailed analysis →
Pros / cons → Risks → Comparison table (when ≥2 entities) → Conclusion →
Sources.

### Follow-ups

`research_reports.parent_id` chains a conversation. A follow-up prompt includes
the parent's body + source list, so "iska asar kya hoga?" resolves against the
previous topic without re-searching. New sources found in a follow-up are
appended with new numbers; old numbers stay stable so earlier citations remain valid.

### Scheduled research

`workmanager` periodic task (minimum 15 min; we use exact-time wake where the OS
allows, else the nearest period) reads `scheduled_research.next_run_at`, runs the
question in `quick` or `deep` mode, writes a report, fires a notification.
Every report carries date, topic, key updates, sources, risks, conclusion — the
same skeleton, so a scheduled brief and a manual one look identical.

Uniqueness guard: one run per schedule per due-time, keyed by
`(schedule_id, due_at)` in settings, so a wake that fires twice cannot double-post.

---

## 8. Projects / Spaces (Phase 7)

A project is a **context bundle**, not a folder:

```
Project
  name, description
  instructions      → prepended to ManagerBot's system context
  chats             → chat_messages.project_id
  reports           → research_reports.project_id
  files, media      → media_files.project_id, project_files
  saved links       → saved_links.project_id
  search_prefs      → provider order + trust threshold for THIS project
```

Composer gets a project chip. When set, `ManagerBot` builds context as:
project instructions → last 3 report summaries → file index (names + one-line
each) → then the normal chat history. Bounded to ~4k tokens; anything larger is
summarised rather than truncated silently.

Deleting a project asks twice and lists what will go (n reports, n files) — no
accidental loss.

---

## 9. Crypto Research Mode (Phase 8)

A preset over the research engine, not a separate engine. It builds a fixed
query fan-out: latest news · official project updates (site/blog/GitHub) ·
GitHub activity (commits in 90 days) · listings/delistings · token unlocks ·
sentiment summary. Output adds two fixed sections — *Bullish factors* and
*Bearish factors* — plus a permanent footer: "Ye financial advice nahi hai.
MyBot trade nahi karta." Sources are mandatory; without them the mode refuses
and says **"Reliable source nahi mila."**

---

## 10. Internal knowledge search (Phase 9)

FTS5 over chats, reports, notes, extracted file text and the trading journal.
`KnowledgeIndex.search(q, {projectId, kinds})` returns typed hits with a
snippet and a relevance rank; the Manager routes "maine pichlay hafte BTC ke
bare mein kya notes banaye thay?" to `internal_search` instead of the web.

`"Meri pichli winning trades ka pattern nikalo"` is a **query over `signals`**
(status/outcome × symbol × timeframe × strategy × confidence), not text search —
so `internal_search` has two modes: `text` and `structured`.

---

## 11. Manager Bot routing v2

Unchanged shape: parse → plan → gate → dispatch → merge. What grows is the
dispatch table and the risk table.

| New action | Bot | Risk | Gate |
|---|---|---|---|
| `describe_media` | vision | read_only | none |
| `transcribe_video` | vision | read_only | none |
| `summarize_file` | analyst | read_only | none |
| `extract_tables` | analyst | read_only | none |
| `web_search` | researcher | read_only | none |
| `fetch_page` | researcher | read_only | none |
| `deep_research` | researcher | read_only | none (spends tokens; says so) |
| `internal_search` | researcher | read_only | none |
| `crypto_brief` | crypto_research | read_only | none |
| `save_to_project` | action | reversible | none |
| `export_report` | action | reversible | none |
| `schedule_research` | action | sensitive | **ask** |
| `tap_trade_button` | action | **irreversible** | **always ask** (§12) |

Planner prompt gains this table verbatim, plus one new rule: *"attach_* steps
describe media the user already sent; never plan a step to take a photo or
record unless the user asked for it."*

`AiConfig` change: `ensureRoles()` merges the two new roles
(`research_planner`, `source_critic`) into any saved config that predates them,
with defaults, so an upgrade never leaves a role unmapped. A unit test pins this.

---

## 12. Trading: letting MyBot press Buy/Sell

You asked for this and I will build it. It is the one place where a bug costs
real money, so the design is deliberately narrow — and I want to be plain about
the trade-off rather than bury it: **once this is on, a mis-tap or a stale
screen can open a real position.** Everything below exists to make that
survivable, not impossible.

### What it does

A new action `tap_trade_button(params: {side: buy|sell})`, only reachable when
the user's own message asks for it. It never runs from a plan that was generated
without that ask, never from a schedule, never twice in a row.

### The five gates

1. **Opt-in setting.** `settings.trading.allowOrderTap`, default **off**, behind
   a one-time warning dialog listing exactly what it enables. Existing users
   keep the safe behaviour until they turn it on.
2. **Fresh screen.** Screenshot must be < 20 s old and its package must be
   TradingView. Anything else → refuse.
3. **Read the button.** Vision reads the on-screen control and must confirm a
   label matching the requested side ("Buy"/"Sell"/"Long"/"Short") and the
   symbol on the order form. A mismatch (wrong symbol, disabled button, deposit
   prompt, confirmation sheet) → refuse and show what it saw.
4. **Your tap, every press.** An approval card with the screenshot, the detected
   symbol, side, and the exact button label. One approval = one press. No
   "remember my choice", no standing consent.
5. **Post-press proof.** Screenshot after the tap, stored in `activity_logs`
   with the approval id, so there is always a record of what the app did.

### Hard blocks (not configurable)

- No tapping when STOP BOT is set, or when the phone is locked.
- Cooldown 60 s between any two `tap_trade_button` executions.
- Never a batch: one press per plan, ever.
- Never from `scheduled_research` or any background task.
- Never with the screen scrolled off the button: the tap uses the button's
  accessibility node bounds, verified against the screenshot taken in step 2.

### What stays the same

Nothing else in the trading path changes: the analysis, the signal, the journal,
the "order screen never touched during analysis" rule. `tap_trade_button` is a
separate, explicit step that only exists when you ask for it in words.

---

## 13. UI changes map

| Screen | Change |
|---|---|
| Chat | composer row: `+` (photo/gallery/camera/video/record/file/pdf), mic, speaker, Research, Deep Research, Think Deeply; project chip; attachment preview strip; sources block under answers |
| Home | status card gains "voice on/off" and "research provider: Tavily" chips |
| Approvals | new card type: trade press, with screenshot + detected label |
| AI Settings | new *Search providers* section: Tavily / Perplexity / Brave / Serper keys + test + order; new roles `research_planner`, `source_critic` |
| Research Settings | NEW screen: provider order, trust threshold, max sources, save-to-project default, uncited-answer policy |
| Scheduled Research | NEW screen: list, add, enable/disable, next run, run-now |
| Projects | NEW tab: list, create, open, per-project chat + reports + files + links |
| Logs | filter by media/research; open the attached screenshot per entry |
| Settings | Storage usage, voice mute, video duration cap, order-tap switch (§12), delete-all-data |

---

## 14. Security rules, and where each is enforced

| Rule | Enforced in |
|---|---|
| Keys never exposed | Keystore only; `SecureStore.maskedKey()` for UI; a log redactor strips `sk-`, `tvly-`, `pplx-`, `BSA`, `gho_` patterns before any write |
| Keys never in the APK or repo | nothing in `assets/` or git; CI has no keys; `.gitignore` covers `.env` |
| Private files never sent to a search provider | `SearchClient` only ever receives the query string; file bodies go to the chosen *model* provider only, and the UI says which one before the first send |
| Only extracted text to search | `FileExtractor` output is chunked, never the bytes |
| Delete media / files / projects / reports / history | each has a real delete + a "delete everything" in Settings |
| Research stays private | no share/export except explicit user action; no background upload |
| Permissions on demand | `permission_handler` called inside the action that needs it, with a one-line reason each time |
| Camera/mic/storage only when used | no permission at first launch; onboarding asks nothing |

---

## 15. GitHub Actions update (Phase 13)

Current workflow stays green; changes are additive:

```yaml
- run: flutter pub get
- run: flutter analyze --no-fatal-infos
- run: flutter test
- run: flutter build apk --release        # unchanged artifact name
```

Additions:
- `actions/cache` for `~/.gradle/caches` and `~/.pub-cache` (cuts ~4 min),
- `dart format --output=none --set-exit-if-changed` as a soft gate,
- build matrix later for ABI splits — **not now**, a single `MyBot-APK` is what
  the phone download needs,
- keep JDK 17 and the committed sideload keystore so updates replace cleanly.

One risk to name: the new plugins push the APK toward 75–90 MB. If that happens,
Phase 13 switches to `--split-per-abi` and the artifact becomes
`MyBot-APK-arm64.apk` (his phone is almost certainly arm64), which also cuts the
download in half.

---

## 16. Phase plan, acceptance criteria, effort

| Phase | Deliverable | Done when | Days |
|---|---|---|---|
| 1 | Voice in/out | speak a Roman Urdu command → same plan as typing; reply spoken; mute persists | 2–3 |
| 2 | Photos | gallery + camera + multi + preview/remove → vision answer naming each photo | 2 |
| 3 | Video | record/upload, cap 30s/1m/3m, 6 key frames, timestamped answer, compress | 2–3 |
| 4 | Screenshot + files | PDF page-cited answer, CSV/XLSX table extraction, screenshot OCR | 2 |
| 5 | Tavily + citations | answer with numbered sources + trust badges; provider fallback proven | 2 |
| 6 | Deep Research | 3–8 searches → structured report → saved → exported | 3–4 |
| 7 | Projects | create/open project; context visibly changes answers | 2 |
| 8 | Crypto mode | fixed query fan-out + bullish/bearish + disclaimer | 1 |
| 9 | Internal search | FTS5 over chats/reports/notes/files + structured trade-pattern query | 2 |
| 10 | Scheduled research | daily 08:00 brief arrives as notification, once, with sources | 2 |
| 11 | Trust filter + follow-ups | Low never stated as fact; follow-up resolves previous topic | 1–2 |
| 12 | Export | PDF + Markdown + text from a report | 1 |
| 13 | CI | green run producing `MyBot-APK` with everything above | 0.5 |

**Total ≈ 24–30 days.** Phase 1+2 as agreed first: **4–5 days**.

---

## 17. Risks and the three things I need from you

**Risks**
1. **No device test yet.** Every phase below Phase 1 inherits that uncertainty.
   Mitigation: Phase 1 ships a smoke-test checklist you run once.
2. **Urdu STT quality** is the engine's, not mine. Some phones lack `ur_PK`;
   the parser absorbs the difference, but recognition of dialect words will vary.
3. **Trading autonomy** (§12): the risk is real and it is yours to accept. The
   five gates reduce it to "one confirmed press on a verified screen".
4. **Token cost** grows with media and deep research. Every expensive action shows
   an estimate before it runs, and Usage now breaks down by media vs research.
5. **Plugin weight.** 12 new plugins ≈ +20–30 MB and more native surface; some
   may conflict with AGP 9. I will land them two at a time with a CI run between.

**Decisions I need from you**
1. **Approve Phase 1 + 2** to start coding (the rest follows the same table).
2. Search provider: do you already have a Tavily key, or should I make the first
   build work with none configured (research disabled, everything else fine)?
3. Order-tap: my plan is off-by-default with the warning dialog in §12.3. If you
   want it on by default, say so and I will — but I will not remove the per-press
   confirmation.
