# OpenClaw Integration Guide

ClawTrace accepts telemetry from OpenClaw via OTLP/HTTP. This guide covers everything you need to connect an OpenClaw instance, the exact attributes ClawTrace reads, and example payloads for each data type.

---

## Quick Start

Add the following to your OpenClaw configuration file:

```json
{
  "diagnostics": {
    "enabled": true,
    "otel": {
      "enabled": true,
      "endpoint": "http://localhost:3000",
      "protocol": "http/protobuf",
      "serviceName": "openclaw-gateway",
      "traces": true,
      "metrics": true,
      "logs": true,
      "sampleRate": 1,
      "flushIntervalMs": 30000
    }
  }
}
```

Point `endpoint` at the machine running ClawTrace. If it's on the same machine as OpenClaw, `http://localhost:3000` is correct. For a different machine on your LAN, use that machine's IP address and start ClawTrace with `CLAWTRACE_BIND=0.0.0.0 rails server`.

No authentication is required. All three OTLP endpoints are unauthenticated by convention.

---

## Endpoints

| Method | Path | Accepts | Purpose |
|--------|------|---------|---------|
| `POST` | `/v1/traces` | `application/json`, `application/x-protobuf` | Trace and span data |
| `POST` | `/v1/metrics` | `application/json`, `application/x-protobuf` | Counter, histogram, and gauge metrics |
| `POST` | `/v1/logs` | `application/json`, `application/x-protobuf` | Log records |

All endpoints return `{}` with HTTP 200 on success. This is required by the OTLP spec.

---

## What ClawTrace Reads from Traces

### Resource attributes

ClawTrace reads from `resourceSpans[].resource.attributes`:

| Attribute | Used for |
|-----------|----------|
| `openclaw.session.key` | `agent_id` — primary identifier for the agent. Shown on the Agents page. |
| `service.name` | Fallback `agent_id` when `openclaw.session.key` is absent. |

All other resource attributes are ignored.

### Span fields

From each span in `scopeSpans[].spans[]`:

| Field | Used for |
|-------|---------|
| `traceId` | Links spans to their trace. Truncated to 16 hex chars if 32 chars are provided. |
| `spanId` | Unique span identifier. |
| `parentSpanId` | Parent/child linking for the waterfall tree. Root spans have no `parentSpanId`. |
| `name` | Operation name shown in the waterfall (e.g. `llm.inference`, `tool.exec.web_search`). Also drives span type classification. |
| `startTimeUnixNano` | Span start time. Nanosecond string, converted to UTC. |
| `endTimeUnixNano` | Span end time. Nanosecond string, used to calculate per-span duration. |
| `status.code` | `2` = ERROR — span is marked with an error badge and the trace status becomes `error`. Any other value is treated as OK. |

### Span type classification

ClawTrace maps OTLP span names to internal span types, which control the color and badge in the waterfall:

| Span name (OTLP) | Span type in ClawTrace | Color |
|-----------------|------------------------|-------|
| `openclaw.request` | `agent_run_started` | Teal |
| `openclaw.agent.turn` | `model_call` | Purple |
| `tool.*` (any prefix) | `tool_call` | Blue |
| `openclaw.command.*` (any prefix) | `decision` | Yellow |
| Any span with `status.code = 2` | `error` | Red |
| Last span in the trace (by start time) | `run_completed` | Gray |
| Everything else | `model_call` | Purple |

### Span attributes

All span attributes (`attributes[]` array) are stored as-is in the span's `metadata` JSON field. ClawTrace does not filter or rename span attributes — whatever OpenClaw emits is stored and displayed in the span drawer.

Common attributes from OpenClaw that appear in the drawer:

| Attribute | Description |
|-----------|-------------|
| `gen_ai.response.model` | Model name (e.g. `claude-sonnet-4-6`) |
| `gen_ai.usage.input_tokens` | Prompt token count |
| `gen_ai.usage.output_tokens` | Completion token count |
| `gen_ai.usage.cache_read_tokens` | Cache read token count (optional) |
| `gen_ai.usage.cache_write_tokens` | Cache write token count (optional) |
| `openclaw.agent.duration_ms` | Agent turn latency |
| `openclaw.llm.cost_usd` | Cost in USD (optional) |
| `openclaw.tool.name` | Tool name for `tool.*` spans |
| `openclaw.tool.call_id` | Tool call ID |
| `openclaw.tool.result_chars` | Length of tool result (optional) |
| `error.type` | Error class name on error spans (e.g. `TimeoutError`) |
| `http.status_code` | HTTP status on `http.client.request` spans |
| `http.url` | Request URL |

---

## What ClawTrace Reads from Metrics

Metrics land in the `metrics` table and appear on the **Metrics** page with a per-metric time-series chart.

From each `resourceMetrics[].scopeMetrics[].metrics[]` entry:

| Field | Used for |
|-------|---------|
| `name` | Metric name shown in the UI (e.g. `agent.turns.total`) |
| Metric type key (`sum`, `histogram`, `gauge`) | Determines chart type: line chart for sums, percentile chart for histograms, gauge value for gauges |
| `dataPoints[].attributes` | Stored as `metric_attributes` — shown as filter labels in the UI |
| `dataPoints[].startTimeUnixNano` | Timestamp |

All three metric types are supported: `sum` (counter), `histogram` (P50/P95/P99 estimation), and `gauge`.

---

## What ClawTrace Reads from Logs

Log records land in the `logs` table and appear in two places: the **Logs** index page (filterable by severity and trace ID) and inline in the span drawer on the trace waterfall.

From each log record in `resourceLogs[].scopeLogs[].logRecords[]`:

| Field | Used for |
|-------|---------|
| `traceId` | Links the log to a trace |
| `spanId` | Links the log to a specific span — appears in that span's drawer |
| `severityText` | Severity label shown in the UI (`DEBUG`, `INFO`, `WARN`, `ERROR`, `FATAL`) |
| `severityNumber` | Severity number (stored, not displayed) |
| `body.stringValue` | Log message body |
| `timeUnixNano` | Timestamp |
| `attributes[]` | Stored as `log_attributes` — available for filtering |

---

## Example Payloads

### Trace payload (`POST /v1/traces`)

A single agent turn with one LLM call and one tool call:

```json
{
  "resourceSpans": [{
    "resource": {
      "attributes": [
        { "key": "service.name", "value": { "stringValue": "openclaw-gateway" } },
        { "key": "openclaw.session.key", "value": { "stringValue": "discord:12345" } }
      ]
    },
    "scopeSpans": [{
      "spans": [
        {
          "traceId": "a1b2c3d4e5f6a7b8",
          "spanId": "1111111111111111",
          "name": "agent.turn.process",
          "startTimeUnixNano": "1714000000000000000",
          "endTimeUnixNano":   "1714000001200000000",
          "status": { "code": 1 },
          "attributes": [
            { "key": "openclaw.agent.duration_ms", "value": { "intValue": 1200 } }
          ]
        },
        {
          "traceId": "a1b2c3d4e5f6a7b8",
          "spanId": "2222222222222222",
          "parentSpanId": "1111111111111111",
          "name": "llm.inference",
          "startTimeUnixNano": "1714000000100000000",
          "endTimeUnixNano":   "1714000000750000000",
          "status": { "code": 1 },
          "attributes": [
            { "key": "gen_ai.response.model",    "value": { "stringValue": "claude-sonnet-4-6" } },
            { "key": "gen_ai.usage.input_tokens", "value": { "intValue": 1800 } },
            { "key": "gen_ai.usage.output_tokens","value": { "intValue": 60 } }
          ]
        },
        {
          "traceId": "a1b2c3d4e5f6a7b8",
          "spanId": "3333333333333333",
          "parentSpanId": "1111111111111111",
          "name": "tool.exec.web_search",
          "startTimeUnixNano": "1714000000800000000",
          "endTimeUnixNano":   "1714000001150000000",
          "status": { "code": 1 },
          "attributes": [
            { "key": "openclaw.tool.name",         "value": { "stringValue": "web_search" } },
            { "key": "openclaw.tool.result_chars",  "value": { "intValue": 2048 } }
          ]
        }
      ]
    }]
  }]
}
```

This produces one trace (`discord:12345`) with three spans. The waterfall shows:

```
agent.turn.process          1.2s
  llm.inference   [Model Call]   650ms
  tool.exec.web_search [Tool Call]  350ms
```

### Error span

A span with `status.code: 2` is stored as type `error` and the entire trace status is set to `error`:

```json
{
  "spanId": "4444444444444444",
  "parentSpanId": "1111111111111111",
  "name": "tool.exec.web_search",
  "startTimeUnixNano": "1714000000800000000",
  "endTimeUnixNano":   "1714000001800000000",
  "status": { "code": 2, "message": "timeout" },
  "attributes": [
    { "key": "error.type",       "value": { "stringValue": "TimeoutError" } },
    { "key": "http.status_code", "value": { "intValue": 0 } }
  ]
}
```

### Metrics payload (`POST /v1/metrics`)

```json
{
  "resourceMetrics": [{
    "resource": {
      "attributes": [
        { "key": "service.name", "value": { "stringValue": "openclaw-gateway" } }
      ]
    },
    "scopeMetrics": [{
      "metrics": [
        {
          "name": "agent.turns.total",
          "sum": {
            "dataPoints": [{
              "startTimeUnixNano": "1714000000000000000",
              "asInt": 1,
              "attributes": [
                { "key": "channel", "value": { "stringValue": "discord" } },
                { "key": "model",   "value": { "stringValue": "claude-sonnet-4-6" } }
              ]
            }]
          }
        },
        {
          "name": "agent.response.latency",
          "histogram": {
            "dataPoints": [{
              "startTimeUnixNano": "1714000000000000000",
              "count": 1,
              "sum": 1200.0,
              "bucketCounts": [0, 0, 1, 0, 0],
              "explicitBounds": [100, 500, 1000, 2000],
              "attributes": [
                { "key": "channel", "value": { "stringValue": "discord" } }
              ]
            }]
          }
        }
      ]
    }]
  }]
}
```

### Logs payload (`POST /v1/logs`)

```json
{
  "resourceLogs": [{
    "resource": {
      "attributes": [
        { "key": "service.name", "value": { "stringValue": "openclaw-gateway" } }
      ]
    },
    "scopeLogs": [{
      "logRecords": [
        {
          "timeUnixNano": "1714000000050000000",
          "severityText": "INFO",
          "severityNumber": 9,
          "body": { "stringValue": "Agent turn started" },
          "traceId": "a1b2c3d4e5f6a7b8",
          "spanId":  "1111111111111111",
          "attributes": [
            { "key": "openclaw.session.key", "value": { "stringValue": "discord:12345" } }
          ]
        },
        {
          "timeUnixNano": "1714000001180000000",
          "severityText": "WARN",
          "severityNumber": 13,
          "body": { "stringValue": "web_search timed out after 1000ms" },
          "traceId": "a1b2c3d4e5f6a7b8",
          "spanId":  "4444444444444444",
          "attributes": [
            { "key": "error.type", "value": { "stringValue": "TimeoutError" } }
          ]
        }
      ]
    }]
  }]
}
```

The WARN log appears inside the tool span's drawer on the trace waterfall because `spanId` matches that span.

---

## Protobuf

All three endpoints accept `application/x-protobuf` (proto3 binary encoding) in addition to JSON. Set `"protocol": "http/protobuf"` in your OpenClaw config to use binary encoding — this is the recommended default.

---

## Troubleshooting

**Traces not appearing**

- Confirm the Rails server is running (`rails server`)
- Check `http://localhost:3000` is reachable from the machine running OpenClaw
- Verify `flushIntervalMs` — OpenClaw buffers telemetry and sends in batches. Default is 30s. Trigger a trace, then wait the flush interval before checking the UI.
- Check the Rails server log for errors on `POST /v1/traces`

**"No data yet" on the Traces page after seeding**

Run `rails db:seed` to create demo traces. The seed is idempotent.

**Spans appear but the waterfall is flat (no hierarchy)**

`parentSpanId` links are missing or incorrect in the payload. Every non-root span must include a `parentSpanId` that matches the `spanId` of its parent.

**traceId is 32 chars, but ClawTrace shows 16**

ClawTrace truncates OTLP 32-char trace IDs to 16 chars for storage. This is intentional — the first 16 chars are used as the trace identifier throughout the UI.
