# Changelog

## [0.2.3] - 2026-04-23

### Changed
- **README screenshots** — replaced stacked hero images with a single constrained `trace-waterfall` shot (width=700), threaded `trace-compare` and `related-trace-logs` inline with their feature sections, and added a 2×2 gallery (dashboard, agents, metrics, logs) before the Roadmap. Updated all screenshot assets to reflect current UI.

## [0.2.2] - 2026-04-23

### Added
- **Trace comparison** — compare two traces side-by-side from either the trace show page (dropdown under the stat strip) or the traces index (check any two traces, hit Compare). Older trace is always A (left), newer is always B (right), regardless of selection order.
- **Comparison stat strip** — five tiles showing input tokens, output tokens, estimated cost, duration, and error count for both traces, with signed deltas (green = improvement, red = regression).
- **Span diff coloring** — spans shared between both traces are highlighted; spans unique to each side are dimmed with a colored left border, making structural differences immediately visible.
- **Cost in comparison** — estimated cost now appears in the comparison stat strip alongside token and duration deltas.

### Fixed
- `span_cost_usd` was computed correctly by `OtlpNormalizer` but silently dropped by `TelemetryIngester` — it was missing from the `Span.create!` column list. All new traces now have cost stored.
- `@compare_candidates` dropdown showed `openclaw.request` for every entry — changed to `traceId[0..7] · status · timestamp` for meaningful differentiation.

## [0.2.1] - 2026-04-23

### Added
- **Solarized Light theme** — opt-in light theme via a sun/moon toggle in the nav. Full Solarized Light palette with `prefers-color-scheme` detection and localStorage persistence. FOUC prevention via inline `<head>` script. Span-type colors map to Solarized equivalents while preserving semantic intent.

### Fixed
- Traces index `ArgumentError: comparison of Float with String failed` — `cost&.> (0)` had a spacing-induced parse error causing Ruby to pass a string to `Float#>`. Fixed to `(cost.to_f > 0)`.

## [0.2.0] - 2026-04-23

### Added
- **Cost tracking** — `span_cost_usd` computed on every model_call span during OTLP ingestion using live pricing from the LiteLLM community JSON (cached 24h with stale fallback). Estimated cost appears on the traces index, trace summary strip, and per-span in the waterfall drawer.
- **Model rate display** — per-span waterfall drawer shows input and output rate per 1M tokens alongside the span cost.
- **Daily budgets** — set a daily spend limit per agent on the agent detail page. `AgentBudget` model with DB-backed unique constraint per agent.
- **BudgetChecker** — run on a cron schedule to alert when agents exceed daily limits. Prints to stdout, pipes cleanly to `terminal-notifier` (macOS) or `notify-send` (Linux). README includes three crontab examples.
- **Cost backfill** — `bin/rails spans:backfill_cost` idempotently backfills `span_cost_usd` for spans ingested before cost tracking was enabled.
- **ModelPricingService** — fetches pricing from the LiteLLM community JSON with suffix-strip model matching (`claude-haiku-4-5-20251001` → `claude-haiku-4-5` → `claude-haiku`), 24-hour cache, and stale-cache fallback.

### Fixed
- `span_cost_usd` stored as `nil` (not `0.0`) for unknown models so the UI correctly shows `—` rather than `$0.000000`.
- Traces index `@costs` query uses a subquery instead of materializing all trace IDs, avoiding SQLite's 999 bind-variable limit.
- `ModelPricingService#fetch_remote` validates HTTP response code before parsing JSON to handle non-JSON error bodies from rate-limited CDNs.
- `BudgetChecker#excess_pct` zero-division guard when `daily_limit_usd` is 0.

## [0.1.2] - 2026-04-20

### Added
- **OTLP log ingestion** — `POST /v1/logs` accepts OTLP log payloads from OpenClaw. Logs are stored with trace ID, span ID, severity, and structured attributes, and can be viewed inline in the waterfall drawer and on a dedicated All Logs panel.
- **Log correlation in the plugin** (`@clawtrace-io/clawtails`) — emits OTLP logs stamped with `traceId`/`spanId` at agent end. Tool params and result text captured per tool call. Configurable via `logs.enabled` and `logs.includeToolCalls` in plugin config.
- **Metric dashboard tiles** — each metric on the dashboard shows a stat tile with current value, period-over-period delta, and sparkline chart. Period filter (12h / 24h / 7d / 30d) controls all tiles.
- **Hourly metric aggregation** — metrics are bucketed by hour, enabling time-series charts and period comparisons without unbounded table growth.
- **Time-series chart** per metric on the metric detail page.
- **Metric status** indicator in the status bar.
- **Trace ID link** in the log drawer — clicking opens the parent trace.
- **Pretty JSON** rendering in log body and span drawer for structured payloads.
- **Retention defaults on first boot** — default prune thresholds applied via initializer so new installs start with sane settings.
- **AI workflow documentation** — `docs/ai-development.md` explains how ClawTrace was built with Claude Code.

### Changed
- **Metrics page redesign** — one summary row per metric name; hourly bucket detail replaces raw event rows.
- **Waterfall drawer** shows log count badge per span instead of inline log frame; logs load on demand.
- **Span drawer** refactored — log count badge, trace ID link, and structured JSON body.
- **Plugin renamed** to `@clawtrace-io/clawtails`. Shared trace-building helpers extracted to `trace-helpers.js` for dev tooling (seed, test-replay).
- **Plugin config** migrated to `api.pluginConfig` accessor; `configSchema` extended with log toggle fields.
- **README** rewritten with install instructions, feature overview, and OpenClaw integration guide.

### Removed
- **Histogram metrics** — lifetime-total histogram rows purged; histogram rendering and `HistogramPercentileCalculator` removed. Replaced by hourly bucket aggregation.
- **Bearer token authentication** — removed from OTLP endpoints (was blocking local-first use; authentication is out of scope for v0.1).
- **Log-association panels** on trace/agent detail pages — replaced by the waterfall-integrated log drawer.

### Fixed
- Plugin config nesting corrected in `0.1.2`.
- Log drawer cutoff on long bodies.
- `\n` escape sequences in JSON bodies rendered as real newlines.
- `tool_calls_chart` queried `tool_result` spans instead of `tool_call` spans.
- Response stream consumed in OTLP/logs fetch to prevent socket exhaustion.
- Subsystem filter uses `openclaw.subsystem` attribute key consistently.
- `ToolCallAnalyzer` reads `tool.name` metadata key and `span_outcome` correctly.
