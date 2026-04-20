# Changelog

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
