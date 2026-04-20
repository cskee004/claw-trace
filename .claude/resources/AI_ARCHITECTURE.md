# AI Architecture Guide

## Purpose of This Document

This file defines the **technical architecture of ClawTrace**.

The goal is to ensure the AI assistant understands how the system is structured so it can implement new features **without introducing architectural drift**.

All new code should follow the architectural patterns defined in this document.

---

# System Overview

**ClawTrace** is an Agent Observability Control Plane built specifically for OpenClaw.

It collects telemetry from OpenClaw agents, stores execution events, and provides analysis and visualization of agent behavior.

The platform is implemented as a **Ruby on Rails application**.

Responsibilities:
- telemetry ingestion (OTLP/HTTP)
- event normalization
- event storage
- analysis services
- dashboard views

---

# Ingestion Path

ClawTrace receives telemetry from OpenClaw via OTLP/HTTP.

## OTLP API (OpenClaw-native)

- Endpoints: `POST /v1/traces`, `POST /v1/metrics`, `POST /v1/logs`
- Auth: none — unauthenticated by OTLP spec convention
- Audience: OpenClaw instances with `diagnostics.otel.enabled = true`
- Format: OTLP/JSON or OTLP/protobuf (proto3)
- Services: `OtlpNormalizer` → `TelemetryIngester` (traces); `MetricsNormalizer` → `Metric.insert_all!` (metrics); `LogsNormalizer` → `Log.insert_all!` (logs)
- Returns: `{}` HTTP 200 (required by OTLP spec)

## What must never happen

- Do not add Bearer token auth to the OTLP endpoint — it breaks OpenClaw compatibility
- Do not bypass `TelemetryIngester` for trace/span writes — all storage goes through it

---

# System Layers

```
OpenClaw Agents
↓
Telemetry Ingestion (OTLP/HTTP)
↓
Event Normalization (OtlpNormalizer)
↓
Event Storage (traces + spans tables)
↓
Analysis Services (app/lib/ analyzers)
↓
Dashboard (Hotwire/Turbo views)
```

Each layer should remain loosely coupled.

---

# Telemetry Model

Agent behavior is represented using a **Trace → Span model** inspired by OpenTelemetry distributed tracing.

## Trace

A trace represents **one complete execution of an agent performing a task**.

Fields:
- `trace_id` (primary key, indexed)
- `agent_id` (indexed)
- `task_name`
- `start_time`
- `status` — `in_progress`, `success`, `error`

Note: `end_time` is not stored on the trace. Duration is computed at runtime from span timestamps via `Trace#duration`.

## Span

A span represents **a single step in a trace**.

Fields:
- `trace_id` (FK to traces, indexed)
- `span_id`
- `parent_span_id`
- `span_type`
- `span_name` — OTLP operation name (e.g. `agent.turn.process`); nil for Bearer-token spans
- `timestamp`
- `end_time` — actual end time from OTLP payload; nil for Bearer-token spans
- `agent_id` (indexed)
- `metadata` (JSON)

---

# Span Type Taxonomy

`span_type` is derived from the OTLP span name via prefix rules (first match wins):

| Prefix | `span_type` |
|--------|------------|
| `openclaw.model.*` | `model_call` |
| `openclaw.message.*` | `message_event` |
| `openclaw.session.*` | `session_event` |
| `openclaw.command.*` | `command_event` |
| `openclaw.webhook.*` | `webhook_event` |
| `openclaw.tool.*` or `tool.*` | `tool_call` |
| `openclaw.*` (catch-all) | `openclaw_event` |
| (anything else) | `span` |

Error state is tracked in `span_outcome` (not `span_type`). A span has `span_outcome = "error"` when `status.code == 2` or `openclaw.outcome` is in `{error, failed, timeout, timed_out}`.

---

# Metadata Philosophy

All OTLP span attributes are stored verbatim in the `metadata` JSON column. High-value fields from `openclaw.model.usage` spans are additionally promoted to first-class `spans` columns (`span_model`, `span_provider`, `span_*_tokens`, `span_outcome`) for efficient querying.

Example — `openclaw.model.usage` metadata:
```json
{
  "openclaw.channel": "discord",
  "openclaw.provider": "anthropic",
  "openclaw.model": "claude-haiku-4-5-20251001",
  "openclaw.sessionKey": "agent:main:discord:channel:1494326249361899544",
  "openclaw.tokens.input": 2,
  "openclaw.tokens.output": 246,
  "openclaw.tokens.cache_read": 94270,
  "openclaw.tokens.cache_write": 94649,
  "openclaw.tokens.total": 94714
}
```

Never fail on missing optional fields. SQLite has no JSON operators — filter on `metadata` in Ruby or use the first-class columns.

---

# Event Ingestion

## OTLP/HTTP API

- Endpoints: `POST /v1/traces`, `POST /v1/metrics`, `POST /v1/logs`
- Auth: none (unauthenticated by OTLP convention)
- Returns: `{}` with HTTP 200 (required by OTLP spec)
- Normalizers: `OtlpNormalizer` (traces), `MetricsNormalizer` (metrics), `LogsNormalizer` (logs)

OpenClaw configuration (with `@clawtrace-io/clawtails` plugin — recommended):
```json
{
  "plugins": {
    "entries": {
      "clawtails": {
        "enabled": true,
        "config": { "endpoint": "http://localhost:3000" }
      }
    }
  },
  "diagnostics": {
    "enabled": true,
    "otel": {
      "enabled": true,
      "endpoint": "http://localhost:3000",
      "protocol": "http/protobuf",
      "serviceName": "openclaw-gateway",
      "traces": false,
      "metrics": true,
      "logs": false
    }
  }
}
```

The plugin handles traces and logs; `diagnostics.otel` handles metrics only (`traces: false, logs: false`).

---

# OpenClaw OTLP Integration

> **Ground-truth references:**
> - `docs/openclaw-integration.md` — complete attribute tables, span types, and example payloads

## openclaw-clawtrace plugin spans

The `openclaw-clawtrace` plugin (`plugin/` in this repo) is a separate ingestion source. It instruments the OpenClaw agent lifecycle via the Plugin SDK and emits a second OTLP trace per turn — distinct from OpenClaw's native OTLP exporter. **Plugin traces and native OpenClaw traces have different `traceId` values and are not linked in ClawTrace.**

Plugin emits one trace per `agent_end` event, containing:

| Span name | `span_type` | When |
|-----------|-------------|------|
| `openclaw.request` | `openclaw_event` | Always (root) |
| `openclaw.agent.turn` | `openclaw_event` | One per assistant message |
| `openclaw.tool.<name>` | `tool_call` | One per tool call |
| `openclaw.context.compaction` | `openclaw_event` | If compaction fired this turn |
| `openclaw.context.branch_summary` | `openclaw_event` | If branch summary created this turn |
| `openclaw.session.yield` | `openclaw_event` | If subagent yield occurred this turn |

**Key implementation facts:**
- `event.timestamp` is absent on live `after_tool_call` events (only in spike recording harness). Fallback: `Date.now() - durationMs`. Without this fallback, tool spans timestamp to epoch.
- `msg.usage.cost` in `agent_end.messages` is an object `{ input, output, cacheRead, cacheWrite, total }` — use `.total` for `gen_ai.usage.cost_usd`.
- Compaction/branch_summary spans are point-in-time (startMs === endMs). If one fires mid-turn it appears in the turn slice and is emitted correctly. The waterfall must sort by `startTimeUnixNano` to place it correctly (backlog item).
- `agent_end.messages` roles: `user`, `assistant`, `toolResult` (ignored — timing captured via toolBuffer), `custom` (subtype via `customType`), `compactionSummary`, `branchSummary`.
- Only one `customType` observed in the wild: `openclaw.sessions_yield`.

---

## Documented OpenClaw span names

OpenClaw emits 5 span names (as of docs.openclaw.ai/logging):

| Span name | `span_type` | Primary `agent_id` source |
|-----------|-------------|--------------------------|
| `openclaw.model.usage` | `model_call` | `openclaw.sessionKey` |
| `openclaw.message.processed` | `message_event` | `openclaw.sessionKey` |
| `openclaw.webhook.processed` | `webhook_event` | `openclaw.chatId` |
| `openclaw.webhook.error` | `webhook_event` | `openclaw.chatId` |
| `openclaw.session.stuck` | `session_event` | `openclaw.sessionKey` |

## agent_id resolution (first match wins)

1. `openclaw.sessionKey` span attribute
2. `openclaw.chatId` span attribute
3. `service.name` resource attribute
4. `"unknown"` (hard fallback)

## Key span attributes

**`openclaw.model.usage`** (first-class columns + metadata):
- `openclaw.provider` → `span_provider`
- `openclaw.model` → `span_model`
- `openclaw.tokens.input` → `span_input_tokens`
- `openclaw.tokens.output` → `span_output_tokens`
- `openclaw.tokens.cache_read` → `span_cache_read_tokens`
- `openclaw.tokens.cache_write` → `span_cache_write_tokens`
- `openclaw.tokens.total` → `span_total_tokens`

**`openclaw.message.processed`**:
- `openclaw.outcome` → `span_outcome` (e.g. `"completed"`, `"error"`)
- `openclaw.chatId`, `openclaw.messageId`, `openclaw.reason`

**`openclaw.webhook.*`**: `openclaw.webhook`, `openclaw.chatId`, `openclaw.error` (error variant)

**`openclaw.session.stuck`**: `openclaw.state`, `openclaw.ageMs`, `openclaw.queueDepth`

## OTLP attribute format

Attributes arrive as an array of key/value objects:
```json
[
  { "key": "openclaw.sessionKey", "value": { "stringValue": "agent:main:discord:channel:123" } },
  { "key": "openclaw.tokens.input", "value": { "intValue": 450 } },
  { "key": "openclaw.tokens.cache_read", "value": { "intValue": 94270 } }
]
```

Use `OtlpNormalizer#attrs_to_hash` to flatten before processing.
Timestamps arrive as nanosecond strings — convert to ISO8601.

---

# Storage Model

Four tables: `traces`, `spans`, `metrics`, `logs`.

**traces**
- `trace_id` (primary key, indexed)
- `agent_id` (indexed)
- `task_name`
- `start_time`
- `status` — `"success"` or `"error"`

**spans**
- `trace_id` (indexed, FK to traces)
- `span_id`
- `parent_span_id`
- `span_type` — see span taxonomy above
- `span_name` — OTLP operation name
- `timestamp`
- `end_time` (nullable) — from OTLP `endTimeUnixNano`
- `agent_id` (indexed)
- `metadata` (JSON) — all OTLP span attributes verbatim
- `span_model` (nullable) — from `openclaw.model`
- `span_provider` (nullable) — from `openclaw.provider`
- `span_input_tokens` (nullable, integer)
- `span_output_tokens` (nullable, integer)
- `span_cache_read_tokens` (nullable, integer)
- `span_cache_write_tokens` (nullable, integer)
- `span_total_tokens` (nullable, integer)
- `span_outcome` (nullable) — `"error"` or pass-through of `openclaw.outcome`

Unique constraint: `[trace_id, span_id]` on spans.

**Column naming convention:** all `spans` columns use the `span_*` prefix. Never add `name`, `type`, or `id` without the prefix.

**metrics**
- `trace_id` (string, nullable, indexed)
- `metric_name` (string, indexed)
- `metric_type` (string — `"sum"`, `"histogram"`, or `"gauge"`)
- `metric_attributes` (JSON — named `metric_attributes`, not `attributes`; ActiveRecord reserves that name)
- `data_points` (JSON — sum/gauge: `{ "value": 42 }`; histogram: `{ "bucket_counts": [...], "explicit_bounds": [...] }`)
- `timestamp` (datetime, indexed)

**logs**
- `trace_id` (string, nullable, indexed)
- `span_id` (string, nullable, indexed)
- `severity_text` (string, nullable)
- `severity_number` (integer, nullable)
- `body` (text, nullable)
- `log_attributes` (JSON)
- `timestamp` (datetime, indexed)

---

# Analysis Layer

Analysis logic lives in **service classes** in `app/lib/`.

Implemented services (all in `app/lib/` unless noted):
- `TraceDurationCalculator` — execution duration in milliseconds; `.call(trace)` or `.call_many(traces)`
- `ToolCallAnalyzer` — tool call frequency and success rates; input: span collection
- `ErrorRateAnalyzer` — error rate as a percentage and affected trace IDs; input: traces with spans
- `MetricChartBuilder` — builds ApexCharts option hashes and stat-strip data from `Metric` records; `.call(records:, metric_type:)` returns `{ options:, stats: }`
- `TracesHelper` (in `app/helpers/`) — `span_depth_map` for waterfall indentation depth; `span_accent` for type-aware metadata labels in inline preview

Analysis classes must not be placed inside controllers.

---

# Dashboard Layer

Views built with Hotwire (Turbo + Stimulus). Turbo Frames for lazy-loaded panels and inline expansion. Stimulus controllers kept small and single-purpose.

Shipped views:
- Trace list — filterable by agent and status; inline row expansion with lazy-loaded span preview
- Trace show — waterfall timeline (DFS pre-order, depth-indented, real-time via Action Cable); span metadata drawer with logs
- Metrics index — ApexCharts card grid, lazy-loaded per metric via Turbo Frames
- Metrics show — time-series chart (sum or histogram percentiles) with stat strip
- Logs — displayed inline within span drawers on the waterfall view

---

# Architectural Principles

1. Preserve clear separation between ingestion, normalization, storage, analysis, and visualization.
2. Prefer simple and explicit data models.
3. Avoid tight coupling between services.
4. Do not introduce unnecessary frameworks or gems.
5. Maintain Rails conventions where possible.
6. Keep event schemas simple and extensible.
7. `OtlpNormalizer` translates — `TelemetryIngester` stores. Never conflate these responsibilities.

---

# AI Assistant Responsibilities

- Follow this architecture when adding new code
- Do not introduce alternative event models
- Do not perform large structural refactors
- Implement features incrementally
- Keep new components consistent with the Trace → Span design
- Treat OpenClaw OTLP span names as the canonical real-world input format
- Always feed `OtlpNormalizer` output through `TelemetryIngester` — never bypass it
