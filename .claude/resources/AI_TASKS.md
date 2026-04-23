# AI Development Tasks

## How This File Works

This file is the **single source of truth** for task status. Do not track status in CLAUDE.md or anywhere else.

### Numbering rules

- Backlog items have **no task numbers**. A task gets a number only when work begins.
- Numbers are **permanent** once assigned — they appear in git commit messages and must never change.
- To start a task: pick the next available integer (highest number in the Completed list + 1), assign it, move the item to In Progress, and use `(Task N)` in every commit for that task.

### Commit format

```
type: short description (Task N)
```

### Lifecycle

1. New work → **Backlog** (no number, plain description)
2. Work starts → assign number, move to **In Progress**
3. Tests green + committed → move to **Completed** (one line, newest first)

### Mid-task discoveries

If something unexpected comes up that is not the current task, add it to Backlog (no number) and finish the current task first. Do not interrupt a task by starting another.

---

## 🔄 In Progress

---

## ✅ Completed

Newest first. One line per task.

- **Task 164** — Replace `.github/workflows/publish-plugin.yml` — push-to-main + `paths: [plugin/package.json]` trigger; `fetch-depth: 2`, version diff via `jq`, idempotent npm publish + `gh release create`; removes manual release-tag step
- **Task 163** — Create `.github/workflows/ci.yml` — RSpec + RuboCop + Brakeman on PRs and pushes to `main`; `bundler-cache: true`, `tailwindcss:build` + `db:schema:load RAILS_ENV=test` before rspec; moved OTLP fixtures from gitignored `.claude/json-test-files/` to `spec/fixtures/otlp/`; removed `lib/clawtrace/version.rb` (Zeitwerk naming mismatch)
- **Task 162** — Trace comparison UI — compare page, show widget on trace show page, checkboxes on index, span diff coloring (shared vs unique spans highlighted with colored left border)
- **Task 161** — Trace comparison route (`GET /traces/compare`), `TracesController#compare` action, and `span_diff_class` helper in `TracesHelper`
- **Task 160** — Fix: `span_cost_usd` computed by `OtlpNormalizer` but silently dropped by `TelemetryIngester` — added to `Span.create!` column list; all new traces now have cost stored
- **Task 159** — `TraceComparator` service: token, cost, duration, and error count deltas between two traces; five-tile comparison stat strip with signed deltas
- **Tasks 156–158** — Solarized Light opt-in theme — CSS vars, Stimulus controller, sun/moon nav toggle; `prefers-color-scheme` detection with localStorage override; FOUC prevention via inline `<head>` script; span-type colors mapped to Solarized equivalents
- **Task 155** — Model rate display: per-span waterfall drawer shows input/output rate per 1M tokens alongside span cost; schema reference + service docs updated
- **Task 154** — Estimated cost on traces index and per-span cost in waterfall drawer
- **Task 153** — README cost control section: budget alert crontab examples for macOS (`terminal-notifier`) and Linux (`notify-send`)
- **Task 152** — Estimated cost in trace summary strip; cost computation targets spans with `span_model` set (not just `model_call` type)
- **Task 151** — Agent show page: "Cost today" stat tile; daily budget form + CRUD (`AgentBudget` model, unique constraint per agent)
- **Task 150** — `BudgetChecker` service: daily spend vs limit, stdout alerts; pipes cleanly to `terminal-notifier` / `notify-send`
- **Task 149** — `bin/rails spans:backfill_cost` rake task: idempotent cost backfill for spans ingested before cost tracking was enabled
- **Task 148** — Compute `span_cost_usd` on model_call spans during OTLP ingestion via `ModelPricingService`
- **Task 147** — Migration: add `span_cost_usd` to spans table; create `agent_budgets` table + `AgentBudget` model
- **Task 146** — `ModelPricingService`: fetches pricing from LiteLLM community JSON with suffix-strip model matching, 24-hour cache, and stale-cache fallback
- **Task 136** — Published `@clawtrace-io/clawtails` to npm; renamed from `openclaw-clawtrace`; added GitHub Actions publish workflow; fixed plugin config nesting (`plugins.entries.clawtails.config`); updated all docs and banner
- **Task 145** — Drop histogram ingestion (MetricsNormalizer drops histogram data points; migration purges existing rows); MetricStatsService adds agent.turns.total + tool.errors.total tiles with delta% to dashboard; metrics show page uses time-series line chart (hour_bucket x-axis) for sum metrics; status indicator switches from Log.maximum(:timestamp) to Metric.maximum(:updated_at) with 5-minute window
- **Task 144** — Plugin log correlation: plugin emits OTLP logs stamped with traceId/spanId at agent_end; logs render inline in waterfall span drawer with JSON expand; index preview shows total log count; All Logs panel restored with span_id filter; tool_calls_chart span_type bug fixed; trace ID on logs page links to trace detail; log drawer body pretty-prints JSON
- **Task 143** — Fix ToolCallAnalyzer: read `metadata["tool.name"]` (not `"tool_name"`), use `span_outcome != "error"` for success (not boolean metadata); Tool Calls chart now populated from real plugin spans
- **Task 142** — Remove "All Logs" / "Recent Logs" panels from trace + agent pages: OpenClaw doesn't populate traceId in OTLP logs so panels were always empty; dead controller actions + routes removed; backlog item added for correlation research
- **Task 141** — Hourly bucket aggregation: one row per `(metric_key, hour_bucket)`, period filter on metrics index + show page, sums across matching hour buckets
- **Task 140** — Metrics page redesign: drop histograms (meaningless as running aggregates), index is a one-row-per-metric summary table with running totals, show page has horizontal bar chart per attribute series
- **Task 139** — Rolling metric aggregation: `MetricAggregator` upserts by `metric_key`, accumulates sum values and histogram buckets; table stays O(unique series) not O(events)
- **Task 138** — Log drawer: full body + `log_attributes` on row click; `log-detail` Stimulus controller + shared `logs/_log_row` partial (logs index + agents page)
- **Task 137** — Fix log-trace correlation: `LogsNormalizer#hex_or_nil` truncates 32-char OTLP traceId to 16 chars; agents page + trace detail associated logs now resolve correctly
- **Task 135** — agent_request + agent_turn span types + CSS vars + span_accent + onboarding banner (show_plugin_banner?) + 9 new specs; prepares ClawTrace for openclaw-clawtrace companion plugin
- **Task 134** — `openclaw.subsystem` facet: select dropdown on logs index (Ruby-side filter, SQLite-safe); same facet in trace show All Logs via Turbo Frame with auto-submit on change
- **Task 133** — `TokenAggregator` service + dashboard token strip: input/output/cache-read/cache-write/total + cache-hit ratio over selected period; hidden when no data
- **Task 132** — Single-span compact card: `_compact_span.html.erb` with type badge, outcome pill, duration bar, LLM section, metadata, logs frame; `show.html.erb` branches on `@spans.size == 1`
- **Task 131** — Protobuf decoder round-trip specs: model_usage_fixture_proto (10 span attrs, multi-byte varints, resource attrs) + log_fixture_record0_proto (Unicode body, 2 log attrs); 18 new specs, 589 total
- **Task 130** — Document openclaw.log.args raw-string policy in logs-normalizer.md; remove stale Phase 3 "intentional failures" comment from spec
- **Task 129** — Clean AI_ARCHITECTURE.md: remove Bearer token API (Task 103), fix span type taxonomy, fix OpenClaw OTLP section (real attrs, agent_id chain), add first-class span columns to storage model, drop api_keys table
- **Task 128** — Reconcile design/span-taxonomy.md with implementation: §1.2 rewritten for span_outcome split, §1.3 notes error never produced by normalizer, §2 removes stale "implementation is wrong" note, §4 updated to document error_in_span?
- **Task 127** — Rewrite docs/openclaw-integration.md: real span names/attrs, correct agent_id derivation chain, error overlay semantics, all 5 span type tables, ~18 metric names with types, real fixture payloads; drop fictional names
- **Task 126** — Synthetic fixtures for 3 missing OpenClaw span types (webhook.processed, webhook.error, session.stuck); fixture helpers + 24 specs covering span_type, agent_id, span_outcome, metadata fields
- **Task 125** — Add "timed_out" to OUTCOME_ERROR_SET to match taxonomy doc; 1 spec
- **Task 124** — Fix trace status bug: error_in_span? checks both OTLP status.code==2 AND OUTCOME_ERROR_SET via span_outcome; 2 new specs
- **Task 123** — Span drawer: outcome pill + dedicated LLM call section (span_model/provider/tokens); residual metadata dump excludes surfaced keys; fix stale span_type=="error" check in span_preview
- **Task 122** — CSS vars + span_accent for new taxonomy: 8 new --color-span-* vars in :root, module.css badge/waterfall rules rewritten, SpanChartBuilder updated, span_accent dispatches on span_type with first-class column support
- **Task 121** — TelemetryIngester persists first-class span fields (span_model, span_provider, span_*_tokens, span_outcome); all 543 examples green; Phase 4 complete
- **Task 120** — OtlpNormalizer full rewrite: SPAN_TYPE_PREFIXES ordered rules, agent_id from span attrs (openclaw.sessionKey → chatId → service.name), first-class field extraction, OUTCOME_ERROR_SET normalization, remove find_final_span/run_completed/decision
- **Task 119** — Migration + SPAN_TYPES realignment: 8 first-class span columns, new taxonomy (model_call/message_event/tool_call/session_event/command_event/webhook_event/openclaw_event/span), ErrorRateAnalyzer→span_outcome, ToolCallAnalyzer→tool_call, SpanChartBuilder updated, seeds + all specs updated
- **Task 118** — Protobuf decoder: gauge type (field 5), scope_metrics field 2 (old format), sum/histogram data_points field 1; OtlpPayloadDumper wired into all three OTLP controllers; decoder spec field numbers fixed
- **Task 117** — Phase 3: rebuild OTLP specs on real fixtures — intentionally red (50 failures); fixture loader in spec/support/otlp_fixtures.rb; covers normalizer, logs normalizer, otlp_spec, e2e_spec
- **Task 116** — Phase 2: span taxonomy design doc (.claude/resources/design/span-taxonomy.md) — pattern rules, agent_id chain, first-class columns, spec contract
- **Task 115** — ADR 0001: docs/adr/0001-openclaw-payload-scope.md — Path A decision (model reality only), pattern-based taxonomy, rejected alternatives, trigger for revisiting
- **Task 114** — Phase 0.5 fictional-shape audit: punch list of fictional-span bleed in Task 108 (seeds) and Task 112 (integration guide); all hits marked "revisit in Phase 6"; additional finding: Span::SPAN_TYPES validator enshrines fictional taxonomy
- **Task 113** — OpenClaw payload baseline: docs/openclaw-payload-baseline.md from real fixtures; documents both span types, log fixture, openclaw.tokens.total semantics, what OpenClaw does NOT emit; linked from README and AI_ARCHITECTURE.md
- **Task 112** — OpenClaw integration guide: docs/openclaw-integration.md (config, all OTLP attributes read, example payloads for traces/metrics/logs, troubleshooting); link from README
- **Task 111** — README hero screenshots: traces index, waterfall show page, dashboard; fix VERSION constant (moved to ApplicationHelper::APP_VERSION)
- **Task 110** — SQLite readiness: add spans.parent_span_id index; README Data & Storage section (file location, wipe, retention defaults, seeds)
- **Task 109** — Header status indicator: log-based Live/Idle pill, right-aligned in header; version number in nav; nav border extends full height
- **Task 108** — Seed data: 5 traces, 30 spans, 5 metrics, 5 logs from TEST_CASES.md scenarios; idempotent sentinel check
- **Task 107** — Remove modern-normalize CSS pin from importmap (caused MIME type console error on every page)
- **Task 106** — Header rail: page title on index pages, breadcrumbs on show pages (traces/agents/metrics); fix grid overlap; remove inline back links
- **Task 105** — CLAUDE.md housekeeping: removed stale `/checkpoint` and `/health` skill routing rules; README Windows dev setup note (`bin/dev` foreman caveat + workaround)
- **Task 104** — Bind Puma to `127.0.0.1` by default; `CLAWTRACE_BIND` env var opt-in for LAN exposure; README Network & Security section; README local-first cleanup (drop stale Postgres requirement, change OpenClaw example endpoint to `http://localhost:3000`)
- **Task 103** — Remove Bearer token API: deleted controllers, model, specs, docs, dropped api_keys table, removed routes
- **Task 102** — Empty state: replace bare "No data" text with OpenClaw config snippet (shared partial, all four index pages)
- **Task 101** — Settings view rewrite: three-section Data Retention card (Logs/Traces/Metrics), all with retention forms, Prune buttons, Delete All buttons
- **Task 100** — SettingsController refactor: generic update (RETENTION_KEYS whitelist), prune_traces/delete_all_traces/prune_metrics/delete_all_metrics/delete_all_logs actions + routes
- **Task 99** — MetricPruner service: delete_all where timestamp < cutoff, returns { deleted: N }, spec
- **Task 98** — TracePruner service: pluck old IDs, delete spans then traces, leave logs untouched, returns { deleted: N }, spec
- **Task 97** — Settings page view: Data Retention card, log retention form, Prune Logs Now button with turbo-confirm
- **Task 96** — SettingsController (show/update/prune_logs), singular resource routes, Settings nav link
- **Task 95** — logs:prune rake task: reads Setting, calls LogPruner, prints result
- **Task 94** — LogPruner service: delete_all where timestamp < cutoff, returns { deleted: N }, spec
- **Task 93** — Setting model: settings table migration (key unique, value text), get/set class methods, model spec
- **Task 92** — Time-window filter on agent inventory: TimeWindowFilter concern applied to AgentsController + period filter UI
- **Task 91** — Extract TimeWindowFilter concern from DashboardController (pure refactor)
- **Task 90** — Recent Logs section on agent show page: lazy Turbo Frame, logs action, _recent_logs partial
- **Task 89** — All Logs section on trace show page: lazy Turbo Frame, logs action, _all_logs partial
- **Task 88** — Logs index page: LogsController, severity + trace_id filters, Turbo Frame table, nav link
- **Task 87** — severity_badge_class ApplicationHelper method + spec + severity badge CSS + span drawer uses helper
- **Task 86** — Agent show page: stat strip (total runs, successes, errors, error rate, avg duration, last seen) + top tools table + recent traces table
- **Task 85** — AgentsController + routes + Agents nav link + inventory index view
- **Task 84** — AgentAggregator service: total_runs, success/error counts, error_rate, avg_duration_ms, last_seen, top_tools (5 max)
- **Task 83** — Dashboard time interval filter: 12h/24h/7d/30d/Custom buttons; `set_period` before_action; hour/day grouping; custom date form via Stimulus
- **Task 82** — Dashboard page: stat strip (traces, agents, error rate) + error rate and traces volume charts; Dashboard nav link
- **Task 81** — Error rate over time chart on traces index (last 30 days, grouped by day, `ErrorRateAnalyzer`)
- **Task 80** — Tool call frequency chart per trace on trace show page (`ToolCallAnalyzer`, lazy Turbo Frame)
- **Task 79** — Span duration breakdown chart on trace show page (`SpanChartBuilder`, horizontal bar, per-span colors)
- **Task 78** — Assert `Span.count` unchanged alongside `Trace.count` on multi-trace rollback
- **Task 77** — Dark-theme CSS overrides for ApexCharts toolbar dropdown menu
- **Task 76** — Tooltip on P50/P95/P99 stat strip labels explaining each percentile
- **Task 75** — ApexCharts dark theme defaults: `withTheme()` in Stimulus controller sets `foreColor`, `grid.borderColor`, `tooltip.theme`
- **Task 74** — Gauge metric type: `MetricChartBuilder` branch, stat strip, `metric-type-badge--gauge` (green)
- **Task 73** — Lazy tool calls chart Turbo Frame on metrics index
- **Task 72** — MetricChartBuilder `{ options:, stats: }` return shape + stat strip above chart + `load_chart_data` helper
- **Task 71** — Lazy Turbo Frame per metric on metrics index with empty-state guard
- **Task 70** — Replace metrics index table with ApexCharts card grid
- **Task 69** — `MetricChartBuilder` service with tests; MetricsController delegates chart building to it
- **Task 68** — Error status icon on inline preview rows
- **Task 67** — Span start-offset and type-aware `span_accent` attribute in inline preview
- **Task 66** — Show all spans in inline preview; remove 8-span limit and count line
- **Task 65** — Readable chevron size and duration color on trace list
- **Task 64** — Whole-row click for inline trace expansion with anchor guard
- **Task 63** — Chevron affordance on waterfall rows (folded into Tasks 60/64)
- **Task 62** — Waterfall bar alignment precision: `round(4)`, 100% clamp, drop `min-width: 4px`
- **Task 61** — Drawer depth-indent alignment matches parent row indent
- **Task 60** — Waterfall drawers default to expanded on page load
- **Task 59** — Waterfall 3-column grid layout (label 45% / bar fill / duration 64px gutter)
- **Task 58** — Font consistency pass: task cell `font-medium fg`, spans count sans-medium
- **Task 57** — Human-readable time display: `format_time_relative` / `format_time_absolute`, two-line stack in trace list and summary strip
- **Task 55** — Turbo Frame panel isolation on trace show page (`_summary` and `_waterfall` partials)
- **Task 54** — UTF-8 encode error messages in `OtlpController` rescue blocks
- **Task 53** — Atomic multi-trace ingestion: outer `ActiveRecord::Base.transaction` in `OtlpController#create`
- **Task 52** — Handle multiple distinct `traceId` values in a single OTLP payload
- **Task 51** — Fix span tree rendering with DFS pre-order traversal in `TracesController`
- **Task 50** — Handle multiple `resourceSpans` entries in `OtlpNormalizer`
- **Task 49** — Sync `AI_ARCHITECTURE.md` with current implementation
- **Task 48** — Rename `spans.name` → `spans.span_name` to follow `span_*` prefix convention
- **Task 47** — Session ID filter on trace list
- **Task 46** — Indent timeline spans by parent depth (16px per level)
- **Task 45** — Display `span_name` in trace timeline alongside span type badge
- **Task 44** — Store span name from OTLP payloads via `OtlpNormalizer` + `TelemetryIngester`
- **Task 43** — Add `name` (later renamed `span_name`) column to `spans` table
- **Task 42** — Gauge metric type support in `MetricsNormalizer`
- **Task 40** — Logs docs and schema (`docs/services/logs-normalizer.md`, `docs/api/otlp.md`, `docs/reference/schema.md`)
- **Task 39** — Span log drawer UI: lazy-loaded logs section inside the waterfall drawer
- **Task 38** — Protobuf support for `/v1/logs` (`OtlpProtobufDecoder.decode_logs`)
- **Task 37** — `POST /v1/logs` controller and route
- **Task 36** — `LogsNormalizer` service
- **Task 35** — `logs` table and `Log` ActiveRecord model
- **Task 34** — Non-scalar attribute validation in `OtlpNormalizer` / `OtlpProtobufDecoder`
- **Task 33** — Store `end_time` per span from OTLP `endTimeUnixNano`; accurate per-span duration in waterfall
- **Task 28** — Real-time trace ingestion via Turbo Streams (Action Cable `TraceChannel`, broadcast on ingest)
- **Task 27** — Inline trace row expansion with lazy-loaded span preview drawer
- **Task 26** — Waterfall span timeline view with DFS ordering, depth indentation, and span-type bar colors
- **Task 25** — Restyle trace list with Tailwind + Turbo Frame filter
- **Task 24** — Add Tailwind CSS (`tailwindcss-rails` gem, Tokyo Night CSS variables, Google Fonts)
- **Task 23** — Metrics UI: index list + time-series show page (ApexCharts)
- **Task 22** — `POST /v1/metrics` controller and route
- **Task 21** — `MetricsNormalizer` service
- **Task 20** — `metrics` table and `Metric` ActiveRecord model
- **Task 19** — Protobuf support for OTLP endpoints (`OtlpProtobufDecoder` with `decode_traces` / `decode_metrics`)
- **Phase 7** — Metrics Ingestion complete (`MetricsNormalizer`, `Metric`, `/v1/metrics`, Metrics UI)
- **Phase 6** — OTLP Ingestion complete (`OtlpNormalizer`, `POST /v1/traces`, end-to-end validation)
- **Phase 5** — Analysis Engine complete (`TraceDurationCalculator`, `ToolCallAnalyzer`, `ErrorRateAnalyzer`)
- **Phase 4** — Observability UI complete (trace list and waterfall timeline views)
- **Phase 3** — Ingestion API complete (Bearer token auth, `TelemetryIngester`, `ApiKey`)
- **Phase 2** — Data Model complete (`traces` and `spans` tables, ActiveRecord models)
- **Phase 1** — Simulator complete (removed after serving its purpose)

---

## 📋 Backlog

Sorted by shipping priority. No task numbers yet — assigned when work begins.

### P1 — Ship blockers

- ~~**README rewrite + screenshot refresh**~~ — DONE (2026-04-20). README rewritten to lead with clawtails, screenshots refreshed with live data, Service Layer table updated.

### CI/CD Pipeline (design approved 2026-04-23)

Implement the two-workflow CI/CD pipeline from `chris-cicd-pipeline-design-20260423-105049.md`. Ship in order — CI first so it gates the publish workflow commit itself.

- ~~**Create `.github/workflows/ci.yml`**~~ — DONE (Task 163). Green on PR #5.
- ~~**Replace `.github/workflows/publish-plugin.yml`**~~ — DONE (Task 164). Awaiting merge.
- ~~**Verify CI passes on first push**~~ — DONE. PR #5 CI green: rspec ✓ rubocop ✓ brakeman ✓.
- **Smoke-test the publish workflow** — Bump `plugin/package.json` version in a PR, merge to `main`, confirm the publish workflow fires (not CI), npm package appears at new version, and a GitHub Release is created automatically. Verify a second re-run is a no-op.

### P2 — Ship soon after

- ~~**Plugin DRY — extract shared buildAndSend logic**~~ — DONE (2026-04-20). Extracted `toMs`, `makeSpan`, `toOtlpAttrs`, `extractRequestAttrs`, `makeSpanId`, `makeLogEntry`, and `buildOtlpPayload` into `plugin/trace-helpers.js`. `seed.js` and `test-replay.js` now import from it. `index.js` stays self-contained (published package). `trace-helpers.js` added to `.npmignore` and `"files"` allowlist updated to `["index.js"]`.

- ~~**docs/api/otlp.md full rewrite**~~ — DONE (2026-04-20). Rewrote span type table from real SPAN_TYPE_PREFIXES, fixed agent_id section, added dual token convention table (openclaw.tokens.* + gen_ai.usage.*), added clawtails as recommended path at top.

- ~~**README curl example — real OpenClaw payload**~~ — DONE (2026-04-20). Added tested curl example using `openclaw.agent.turn` shape with gen_ai token attributes; verified 200 against live server.

### P3 — Post-launch polish

- ~~**Retention defaults on first boot**~~ — DONE (2026-04-20). `config/initializers/default_settings.rb` seeds 30-day defaults for all three retention keys on first boot if not set. Skipped in test env.

- ~~**Remove HistogramPercentileCalculator dead code**~~ — DONE (2026-04-20). Deleted `app/lib/histogram_percentile_calculator.rb` and its spec. 632 examples, 0 failures.

- ~~**plugin/package.json: add files allowlist**~~ — DONE (2026-04-20). Added `"files": ["index.js"]` to package.json.

- **Two-path visual in README** — Empty state and README now both cover the two-path story. Remaining gap: no inline screenshot/comparison in README showing compact card vs full waterfall. Low priority post-launch.

- **CLAUDE.md: add doc-update step to task completion checklist** — Add: "Update README Features section if the task adds a user-facing capability." Ten consecutive tasks (135-145) shipped without README updates, causing the current stale docs state.

- **OpenClaw health check in status bar** — Requires OpenClaw to expose a health endpoint. Deferred.

- **Waterfall timeline mode** — Acceptable for v0.1. Deferred.

- **Multi-platform Bearer token API** — Future work. Deferred.

