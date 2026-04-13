# ClawTrace

### Agent Observability for OpenClaw

<!-- CLAUDE_STATS_START -->
#### Claude Code Stats

![sessions: 15](https://img.shields.io/badge/sessions-15-1a1b27?style=for-the-badge&logo=anthropic&logoColor=white) ![API calls: 1,681](https://img.shields.io/badge/API%20calls-1%2C681-7aa2f7?style=for-the-badge&logo=anthropic&logoColor=white) ![tokens: 125.3M](https://img.shields.io/badge/tokens-125.3M-bb9af7?style=for-the-badge&logo=anthropic&logoColor=white) ![thinking time: 56.4m](https://img.shields.io/badge/thinking%20time-56.4m-7dcfff?style=for-the-badge&logo=anthropic&logoColor=white) ![wall clock: 15.9h](https://img.shields.io/badge/wall%20clock-15.9h-3d59a1?style=for-the-badge&logo=anthropic&logoColor=white) ![est. cost: $68.00](https://img.shields.io/badge/est.%20cost-%2468.00-73daca?style=for-the-badge&logo=anthropic&logoColor=white)
<!-- CLAUDE_STATS_END -->

---

### Requirements

* Ruby 3.2 or higher
* Rails 8.0 or higher
* SQLite3 (development / test) or PostgreSQL (production via `DATABASE_URL`)

---

### Description

ClawTrace is a Rails 8 agent observability platform built specifically for [OpenClaw](https://github.com/openclaw/openclaw). It gives developers full visibility into how their agents think, act, and fail — capturing traces, spans, metrics, and logs from live agent runs and surfacing them through a dashboard.

The platform accepts telemetry over two paths: a Bearer token REST API for direct integration, and a native OTLP/HTTP endpoint that OpenClaw targets out of the box. Both paths write to the same storage layer and appear in the same UI.

This project is part of a personal portfolio and demonstrates experience with Ruby, Rails, OpenTelemetry-inspired design, API development, and AI-assisted development using [Claude Code](https://claude.ai/code).

---

### Features

#### Trace & Span Ingestion
- Trace → Span data model inspired by OpenTelemetry distributed tracing
- OTLP/HTTP ingestion via `POST /v1/traces` — accepts `application/json` and `application/x-protobuf`
- Bearer token ingestion via `POST /api/v1/telemetry` for direct API use
- `parent_span_id` linking for full span hierarchy reconstruction
- ERROR status span detection and storage

#### Metrics Ingestion
- OTLP metrics via `POST /v1/metrics` — accepts `application/json` and `application/x-protobuf`
- Handles `sum`, `histogram`, and `gauge` metric types
- Filterable metrics index with per-metric time series view
- P50/P95/P99 estimation from histogram bucket data

#### Log Ingestion
- OTLP logs via `POST /v1/logs` — accepts `application/json` and `application/x-protobuf`
- Log records linked to traces and spans via `trace_id` + `span_id`
- All severity levels stored: DEBUG, INFO, WARN, ERROR, FATAL

#### Analysis Engine
- `TraceDurationCalculator` — execution duration per trace
- `ToolCallAnalyzer` — tool call frequency and success rates
- `ErrorRateAnalyzer` — error rate across traces
- `HistogramPercentileCalculator` — P50/P95/P99 from OTLP histogram buckets

#### Dashboard
- Trace list with status filtering
- Trace timeline with per-span metadata
- Metrics index and time series view
- Built with Hotwire (Turbo + Stimulus)

---

### Setup

```bash
git clone https://github.com/cskee004/claw-trace.git
cd claw-trace
bundle install
rails db:create db:migrate
rails server
```

Visit `http://localhost:3000`.

---

### API

#### OTLP Endpoints (OpenClaw native)

No authentication required — unauthenticated by OTLP convention. All endpoints return `{}` with HTTP 200 on success.

```
POST /v1/traces    — ingest OTLP trace payload (ResourceSpans)
POST /v1/metrics   — ingest OTLP metrics payload (ResourceMetrics)
POST /v1/logs      — ingest OTLP log payload (ResourceLogs)
```

Both `application/json` and `application/x-protobuf` content types are accepted.

OpenClaw configuration:
```json
{
  "diagnostics": {
    "enabled": true,
    "otel": {
      "enabled": true,
      "endpoint": "https://your-clawtrace.com",
      "traces": true,
      "metrics": true
    }
  }
}
```

---

#### Bearer Token API

Register a key, then use the returned token to submit telemetry.

**Register an API key**
```
POST /api/v1/keys
Content-Type: application/json

{ "agent_type": "support-agent" }
```
Response `201 Created`:
```json
{
  "token": "<your-token>",
  "agent_type": "support-agent",
  "message": "Store this token securely — it will not be shown again."
}
```

**Submit telemetry**
```
POST /api/v1/telemetry
Authorization: Bearer <your-token>
Content-Type: text/plain
```

Body is NDJSON — line 1 is the trace record, subsequent lines are span records:
```
{"trace_id":"a1b2c3d4e5f6a7b8","agent_id":"support-agent","task_name":"classify_ticket","start_time":"2026-04-02T12:00:00Z","status":"success"}
{"trace_id":"a1b2c3d4e5f6a7b8","span_id":"s1","parent_span_id":null,"span_type":"agent_run_started","timestamp":"2026-04-02T12:00:01Z","agent_id":"support-agent","metadata":{}}
```

Response `201 Created`:
```json
{ "trace_id": "a1b2c3d4e5f6a7b8", "spans_ingested": 1 }
```

**Revoke a key**
```
DELETE /api/v1/keys/:id
Authorization: Bearer <your-token>
```

---

### Service Layer

All business logic lives in `app/lib/` — never in controllers.

| Class | Responsibility |
|---|---|
| `TelemetryIngester` | Validates and persists traces and spans |
| `OtlpNormalizer` | Translates OTLP trace payloads into the Trace → Span model |
| `MetricsNormalizer` | Translates OTLP metrics payloads into `Metric` records |
| `LogsNormalizer` | Translates OTLP log payloads into `Log` records |
| `OtlpProtobufDecoder` | Pure-Ruby proto3 decoder for binary OTLP payloads |
| `TraceDurationCalculator` | Calculates trace execution duration in milliseconds |
| `ToolCallAnalyzer` | Analyzes tool call frequency and success rates |
| `ErrorRateAnalyzer` | Detects error spans and computes error rate |
| `HistogramPercentileCalculator` | Estimates P50/P95/P99 from histogram bucket data |

---

### Testing

```bash
bundle exec rspec        # full test suite
bundle exec rubocop      # lint
bundle exec brakeman     # security scan
```

Test coverage includes service class unit specs (`spec/lib/`), model specs, and request specs for all API endpoints.

---

### Roadmap

- [x] Trace → Span data model and storage
- [x] Bearer token ingestion API
- [x] OTLP trace ingestion (`/v1/traces`)
- [x] OTLP metrics ingestion (`/v1/metrics`)
- [x] OTLP log ingestion (`/v1/logs`)
- [x] Protobuf support across all three OTLP endpoints
- [x] Analysis engine (duration, tool calls, error rate, histogram percentiles)
- [x] Trace list and timeline dashboard
- [x] Metrics dashboard
- [ ] Tailwind CSS + waterfall span timeline
- [ ] Real-time trace updates via Turbo Streams
- [ ] Dashboard charts (Chartkick + ApexCharts)
- [ ] OpenClaw plugin for one-command installation

---

[![Ruby Style Guide](https://img.shields.io/badge/code_style-rubocop-brightgreen.svg)](https://github.com/rubocop/rubocop)
