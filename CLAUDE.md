# CLAUDE.md

## Commands

```bash
# Setup
bundle install
rails db:create db:migrate

# Run dev server
rails server

# Run all tests
bundle exec rspec

# Run a single test file
bundle exec rspec spec/lib/otlp_normalizer_spec.rb

# Run a single example by line number
bundle exec rspec spec/lib/otlp_normalizer_spec.rb:42

# Lint
bundle exec rubocop
bundle exec brakeman
```

## Reference Documents

- `.claude/resources/AI_ARCHITECTURE.md` — full system architecture, ingestion path design, OTLP span mappings
- `.claude/resources/AI_TASKS.md` — current task list and phase status
- `.claude/open-claw-test-files/TEST_CASES.md` — test cases

---

## Frontend Aesthetics

ClawTrace is a developer observability tool. Visual lineage: Linear, 
Vercel dashboard, Honeycomb, Datadog APM. Favor information density 
and clarity over marketing flourish.

Theme: Tokyo Night palette as the canonical reference. Dark by default. 
Define all colors as CSS variables in a single :root block; never 
inline hex values in markup.

Typography: IBM Plex Sans for UI text, JetBrains Mono for all IDs, 
durations, timestamps, and JSON metadata. Load from Google Fonts. 
Never Inter, Roboto, or system-ui. Use weight extremes (300 vs 700) 
not middle values.

Span-type colors are load-bearing semantics, not decoration — they 
must match across the waterfall, the drawer, and any future charts. 
Defined once in tailwind.config.js, referenced everywhere.

Motion: reserved for real-time span append (Task 28) and drawer 
open/close. No page-load animations, no hover flourishes on rows.

Backgrounds: subtle. A single low-contrast gradient or noise texture 
on the app shell, nothing on data-dense panels.

Avoid: white-and-purple gradients, evenly distributed pastels, 
generic card shadows, emoji icons, rounded-3xl on data rows.

---

## Architecture

**Purpose:** ClawTrace is a Rails 8 agent observability platform built for OpenClaw — giving developers full visibility into how their agents think, act, and fail.

**Service layer** lives in `app/lib/` (not `app/services/`):
- `TelemetryIngester` — validates and stores incoming telemetry events into `traces` and `spans`
- `OtlpNormalizer` — translates OTLP/JSON span payloads from OpenClaw into the Trace → Span model
- `MetricsNormalizer` — translates OTLP metrics payloads into arrays of hashes ready for `Metric.create!`
- `LogsNormalizer` — translates OTLP logs payloads into arrays of hashes ready for `Log.insert_all!`
- `TraceDurationCalculator` — calculates execution duration for traces in milliseconds
- `ToolCallAnalyzer` — analyzes tool call frequency and success rates within traces
- `ErrorRateAnalyzer` — detects traces containing error spans and computes error rate
- `HistogramPercentileCalculator` — estimates P50/P95/P99 from OTLP histogram bucket data
- `OtlpProtobufDecoder` — pure-Ruby proto3 decoder; `decode_traces` / `decode_metrics` / `decode_logs` return the same structure as OTLP/JSON so normalizers need no changes

**Data flows:**
```
# Bearer token ingestion
Agent → POST /api/v1/telemetry (Bearer token) → TelemetryIngester → traces + spans tables

# OTLP trace ingestion
OpenClaw → POST /v1/traces → OtlpNormalizer → TelemetryIngester → traces + spans tables

# OTLP metrics ingestion
OpenClaw → POST /v1/metrics → MetricsNormalizer → Metric.insert_all! → metrics table

# OTLP logs ingestion
OpenClaw → POST /v1/logs → LogsNormalizer → Log.insert_all! → logs table
```

**UI:** Hotwire (Turbo + Stimulus). Dashboard panels update via Turbo frames.

**Database:** SQLite3 (dev/test), PostgreSQL (prod via `DATABASE_URL`).

---

## Current Status

- Phase 1 (Simulator): ✅ Complete — removed after serving its purpose; codebase no longer contains simulator
- Phase 2 (Data Model): ✅ Complete — `traces`, `spans`, and `metrics` tables live
- Phase 3 (Ingestion API): ✅ Complete — Bearer token auth, `TelemetryIngester`, `ApiKey` model
- Phase 4 (Observability UI): ✅ Complete — trace list and timeline views
- Phase 5 (Analysis Engine): ✅ Complete — `TraceDurationCalculator`, `ToolCallAnalyzer`, `ErrorRateAnalyzer`
- Phase 6 (OTLP Ingestion): ✅ Complete — `OtlpNormalizer`, `POST /v1/traces`
- Phase 7 (Metrics Ingestion): ✅ Complete — `MetricsNormalizer`, `Metric` model, `POST /v1/metrics`, Metrics UI
- Phase 8 (UI Polish): 🟡 In progress — Task 24 (Tailwind + Tokyo Night) + Task 25 (trace list restyle) + Task 26 (waterfall span timeline) complete
- Task 19 (Protobuf Support): ✅ Complete — `OtlpProtobufDecoder`, `application/x-protobuf` routing in both OTLP controllers
- Task 26 (Waterfall Span Timeline): ✅ Complete — `show.html.erb` waterfall, `span_detail` Stimulus controller, span-type color tokens
- Tasks 33–49: ✅ Complete — see `AI_TASKS.md` for full task history

**Next up:** Task 27 — Inline Trace Row Expansion

---

## Target Integration — OpenClaw

The primary target is **OpenClaw** (github.com/openclaw/openclaw).
See `AI_ARCHITECTURE.md` for full span mappings, OTLP attribute format, and ingestion path design.

---

## Gotchas

- OTLP attributes arrive as `[{ key:, value: { stringValue: } }]` — use `attrs_to_hash` pattern to flatten
- OTLP timestamps are nanosecond strings — convert to ISO8601 before storing
- `cost_usd`, cache tokens, and context fields from OpenClaw are optional — never fail if absent
- OTLP endpoints must return `{}` with HTTP 200 on success — required by the OTLP spec
- `metric_attributes` not `attributes` — ActiveRecord reserves the `attributes` method name
- Metric names contain dots (e.g. `gen_ai.client.token.usage`) — routes need `format: false` and a `/[^\/]+/` constraint
- Rescue blocks in OTLP controllers must force-encode `e.message` to UTF-8 before rendering JSON — binary protobuf input can make `e.message` non-UTF-8, causing `JSON::GeneratorError`: `e.message.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")`

---

## Ingestion API

### Bearer Token API
- `POST /api/v1/telemetry` — ingest a telemetry event
- `POST /api/v1/keys` — register a new API key

Auth: `Authorization: Bearer <token>` header. Keys managed via `ApiKey` model.
Service: `TelemetryIngester` in `app/lib/`.

### OTLP API
- `POST /v1/traces` — accept OTLP trace payloads from OpenClaw
- `POST /v1/metrics` — accept OTLP metrics payloads from OpenClaw
- `POST /v1/logs` — accept OTLP log payloads from OpenClaw
- All endpoints accept `application/json` and `application/x-protobuf` (proto3)
- No auth required — unauthenticated by OTLP convention
- Returns `{}` with HTTP 200 on success

Services: `OtlpNormalizer` → `TelemetryIngester` (traces); `MetricsNormalizer` → `Metric.insert_all!` (metrics); `LogsNormalizer` → `Log.insert_all!` (logs).

---

## Testing

- Service class specs live in `spec/lib/`
- Controller and request specs live in `spec/requests/`
- New `app/lib/` classes must have corresponding specs in `spec/lib/`
- UI controllers (`TracesController`, `MetricsController`) have no request specs — tested via the browser

---

## AI Collaboration Rules

- Write idiomatic Ruby — small focused methods, clear names, no overly complex abstractions
- Read relevant files before proposing changes
- Make small, incremental changes — one task at a time
- Modify only files relevant to the current task
- Do not rename or delete files unless explicitly instructed
- Place new analysis logic in `app/lib/`, not in controllers
- Request confirmation before any change that touches multiple parts of the system

## Off Limits

- Do not introduce new gems without confirmation
- Do not run `db:drop` or `db:schema:load` — use migrations only
- Do not hardcode API keys or credentials
- Do not modify `OtlpNormalizer` and `TelemetryIngester` in the same task — they have separate responsibilities

## Commit & Push Rules

**Always run the full test suite before committing or pushing.** Never commit failing tests.

```bash
bundle exec rspec
```

Only proceed with `git commit` or `git push` if the result is `0 failures`. If tests fail, fix them first.

**After a successful commit, update `AI_TASKS.md`:**
- Mark the completed task with ✅
- Update the Current Status block in `CLAUDE.md` if a phase changed
- If new tasks were discovered during implementation, add them before the next phase

## Validation Loop

Before considering a task complete, verify:

1. **Architecture fit** — Does new code follow the Trace → Span model? Is logic in `app/lib/` and not in controllers?
2. **Scope** — Were any unrelated files modified? Were any files renamed or deleted without instruction?
3. **Database** — If a migration was added, is it reversible? Are indexed fields for `trace_id` and `span_id` included?
4. **Tests** — Do new `app/lib/` classes have specs in `spec/lib/`?
5. **OTLP** — If touching the OTLP path, does `OtlpNormalizer` feed into `TelemetryIngester` without bypassing it?
6. **Run checks** — `bundle exec rspec`, `bundle exec rubocop`, `bundle exec brakeman`
7. **Docs** — If a REST endpoint was added or changed → update `docs/api/`. If a service class in `app/lib/` was added or changed → update `docs/services/`. If a migration was added → update `docs/reference/schema.md`.
