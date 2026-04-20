# OpenClaw Integration Guide

ClawTrace accepts telemetry from OpenClaw via OTLP/HTTP. This guide covers everything you need to connect an OpenClaw instance, the exact attributes ClawTrace reads, and example payloads for each data type.

---

## Quick Start

### Recommended: clawtails plugin + diagnostics

Install the companion plugin:

```bash
openclaw plugins install @clawtrace-io/clawtails
```

Then add both blocks to `~/.openclaw/openclaw.json`. The plugin handles traces and logs; `diagnostics.otel` handles metrics only:

```json
{
  "plugins": {
    "entries": {
      "clawtails": {
        "enabled": true,
        "config": {
          "endpoint": "http://localhost:3000",
          "logs": {
            "enabled": true,
            "tool_calls": true,
            "assistant_turns": true,
            "user_messages": true,
            "compaction_events": true
          }
        }
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
      "logs": false,
      "sampleRate": 1,
      "flushIntervalMs": 30000
    }
  }
}
```

This gives you the full waterfall view: `openclaw.request → openclaw.agent.turn → openclaw.tool.*` span hierarchy, token usage on each turn, and correlated logs (tool inputs/outputs, assistant messages, compaction events) inline in the span drawer.

### Without the plugin

If you don't want to install the plugin, point OpenClaw's built-in diagnostics directly at ClawTrace:

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

This sends flat spans — each event appears as a compact card, not a waterfall. No parent-child hierarchy, no correlated logs from the agent lifecycle.

---

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
| `service.name` | Fallback `agent_id` when no session context is present in the span attributes. |

All other resource attributes are stored but not otherwise used.

### agent_id derivation

ClawTrace derives `agent_id` from each span's own attributes, using the first match in this chain:

1. `openclaw.sessionKey` span attribute
2. `openclaw.chatId` span attribute
3. `service.name` resource attribute
4. Falls back to `"unknown"`

`agent_id` is what groups spans under an agent on the Agents page. Webhook spans typically carry `openclaw.chatId` but not `openclaw.sessionKey`; model and message spans carry both.

### Span fields

From each span in `scopeSpans[].spans[]`:

| Field | Used for |
|-------|---------|
| `traceId` | Links spans to their trace. Truncated to 16 hex chars if 32 chars are provided. |
| `spanId` | Unique span identifier. |
| `parentSpanId` | Parent/child linking for the waterfall tree. Root spans have no `parentSpanId`. |
| `name` | Operation name shown in the waterfall. Drives span type classification. |
| `startTimeUnixNano` | Span start time. Nanosecond string, converted to UTC. |
| `endTimeUnixNano` | Span end time. Used to calculate per-span duration. |
| `status.code` | `2` = OTLP error — span_outcome becomes `error` and trace status becomes `error`. |

### Span type classification

ClawTrace maps span names to internal types using prefix rules (first match wins):

| Span name prefix | Span type | Waterfall color |
|-----------------|-----------|-----------------|
| `openclaw.model.*` | `model_call` | Purple |
| `openclaw.message.*` | `message_event` | Green |
| `openclaw.session.*` | `session_event` | Teal |
| `openclaw.command.*` | `command_event` | Yellow |
| `openclaw.webhook.*` | `webhook_event` | Orange |
| `tool.*` | `tool_call` | Blue |
| `openclaw.*` (catch-all) | `openclaw_event` | Slate |
| (anything else) | `span` | Dim |

### Error detection

A span's `span_outcome` is set to `"error"` when either condition is true:

- `status.code == 2` (OTLP error code), **or**
- `openclaw.outcome` is one of: `error`, `failed`, `timeout`, `timed_out`

When any span in a trace has `span_outcome = "error"`, the trace's own status is also set to `"error"`. Real OpenClaw spans emit `status.code = 0` even on failure — the `openclaw.outcome` attribute is the primary failure signal.

### Span attributes

All span attributes are stored in the span's `metadata` field and displayed in the span drawer. First-class columns are extracted from model spans for cost reporting.

**`openclaw.model.usage` spans** (LLM API calls):

| Attribute | Description | Stored as |
|-----------|-------------|-----------|
| `openclaw.channel` | Channel name (e.g. `"discord"`) | `metadata` |
| `openclaw.provider` | LLM provider (e.g. `"anthropic"`) | `span_provider` |
| `openclaw.model` | Model name (e.g. `"claude-haiku-4-5-20251001"`) | `span_model` |
| `openclaw.sessionKey` | Session key — primary `agent_id` source | `metadata` |
| `openclaw.sessionId` | Session UUID | `metadata` |
| `openclaw.tokens.input` | Input token count | `span_input_tokens` |
| `openclaw.tokens.output` | Output token count | `span_output_tokens` |
| `openclaw.tokens.cache_read` | Cache-read token count | `span_cache_read_tokens` |
| `openclaw.tokens.cache_write` | Cache-write token count | `span_cache_write_tokens` |
| `openclaw.tokens.total` | Total tokens (as reported by OpenClaw) | `span_total_tokens` |

**`openclaw.message.processed` spans** (message lifecycle):

| Attribute | Description |
|-----------|-------------|
| `openclaw.channel` | Channel name |
| `openclaw.outcome` | Result: `completed`, `error`, `failed`, `timeout`, `timed_out` |
| `openclaw.sessionKey` | Session key |
| `openclaw.sessionId` | Session UUID |
| `openclaw.chatId` | Chat/channel ID |
| `openclaw.messageId` | Message ID |
| `openclaw.reason` | Reason string (optional) |

**`openclaw.webhook.processed` spans** (webhook delivery):

| Attribute | Description |
|-----------|-------------|
| `openclaw.channel` | Channel name |
| `openclaw.webhook` | Webhook event type (e.g. `"message.create"`) |
| `openclaw.chatId` | Chat/channel ID — used as `agent_id` fallback |

**`openclaw.webhook.error` spans** (webhook delivery failure):

| Attribute | Description |
|-----------|-------------|
| `openclaw.channel` | Channel name |
| `openclaw.webhook` | Webhook event type |
| `openclaw.chatId` | Chat/channel ID |
| `openclaw.error` | Error message |

**`openclaw.session.stuck` spans** (stuck session diagnostic):

| Attribute | Description |
|-----------|-------------|
| `openclaw.sessionKey` | Session key |
| `openclaw.sessionId` | Session UUID |
| `openclaw.state` | Session state (e.g. `"waiting"`) |
| `openclaw.ageMs` | Session age in milliseconds |
| `openclaw.queueDepth` | Number of queued messages |

---

## What ClawTrace Reads from Metrics

Metrics land in the `metrics` table and appear on the **Metrics** page with a per-metric time-series chart.

From each `resourceMetrics[].scopeMetrics[].metrics[]` entry:

| Field | Used for |
|-------|---------|
| `name` | Metric name shown in the UI |
| Metric type key (`sum`, `histogram`, `gauge`) | Chart type: line for sums/gauges, percentile bands for histograms |
| `dataPoints[].attributes` | Stored as `metric_attributes` — shown as filter labels in the UI |
| `dataPoints[].startTimeUnixNano` | Timestamp |

All three metric types are supported: `sum` (counter), `histogram` (P50/P95/P99 estimation), and `gauge`.

### OpenClaw metrics reference

All metrics are in the `openclaw.*` namespace. The `openclaw.channel` attribute is present on every data point.

**Model usage**

| Metric | Type | Description |
|--------|------|-------------|
| `openclaw.tokens` | counter | Token count per LLM call |
| `openclaw.cost.usd` | counter | Cost in USD per LLM call |
| `openclaw.run.duration_ms` | histogram | Agent run duration |
| `openclaw.context.tokens` | histogram | Context window token usage |
| `openclaw.run.attempt` | counter | Run attempts (including retries) |

**Message flow**

| Metric | Type | Description |
|--------|------|-------------|
| `openclaw.webhook.received` | counter | Webhooks received |
| `openclaw.webhook.error` | counter | Webhook delivery failures |
| `openclaw.webhook.duration_ms` | histogram | Webhook processing latency |
| `openclaw.message.queued` | counter | Messages queued |
| `openclaw.message.processed` | counter | Messages processed |
| `openclaw.message.duration_ms` | histogram | End-to-end message processing latency |

**Queues and sessions**

| Metric | Type | Description |
|--------|------|-------------|
| `openclaw.queue.lane.enqueue` | counter | Items enqueued per lane |
| `openclaw.queue.lane.dequeue` | counter | Items dequeued per lane |
| `openclaw.queue.depth` | gauge | Current queue depth |
| `openclaw.queue.wait_ms` | histogram | Queue wait time |
| `openclaw.session.state` | gauge | Active session count by state |
| `openclaw.session.stuck` | counter | Sessions detected as stuck |
| `openclaw.session.stuck_age_ms` | histogram | Age of stuck sessions |

---

## What ClawTrace Reads from Logs

Log records land in the `logs` table and appear on the **Logs** index page (filterable by severity and trace ID) and inline in the span drawer on the trace waterfall.

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

Common OpenClaw log attributes:

| Attribute | Description |
|-----------|-------------|
| `openclaw.subsystem` | Source subsystem (e.g. `"gateway/ws"`, `"agent/embedded"`, `"openclaw"`) |
| `openclaw.log.level` | Original log level string |
| `openclaw.log.args` | JSON-encoded structured event payload (optional) |

---

## Example Payloads

### Trace payload — model usage (`POST /v1/traces`)

A single LLM call from a real OpenClaw capture:

```json
{
  "resourceSpans": [{
    "resource": {
      "attributes": [
        { "key": "service.name", "value": { "stringValue": "openclaw-gateway" } }
      ]
    },
    "scopeSpans": [{
      "spans": [{
        "traceId": "3814946c5476f41811f4a6fbb49e81e2",
        "spanId": "6e65a51a6055906b",
        "name": "openclaw.model.usage",
        "startTimeUnixNano": "1776353057612000000",
        "endTimeUnixNano":   "1776353064358000000",
        "attributes": [
          { "key": "openclaw.channel",             "value": { "stringValue": "discord" } },
          { "key": "openclaw.provider",            "value": { "stringValue": "anthropic" } },
          { "key": "openclaw.model",               "value": { "stringValue": "claude-haiku-4-5-20251001" } },
          { "key": "openclaw.sessionKey",          "value": { "stringValue": "agent:main:discord:channel:1494326249361899544" } },
          { "key": "openclaw.sessionId",           "value": { "stringValue": "994956de-f338-41b7-988d-5076b236c2a9" } },
          { "key": "openclaw.tokens.input",        "value": { "intValue": 2 } },
          { "key": "openclaw.tokens.output",       "value": { "intValue": 246 } },
          { "key": "openclaw.tokens.cache_read",   "value": { "intValue": 94270 } },
          { "key": "openclaw.tokens.cache_write",  "value": { "intValue": 94649 } },
          { "key": "openclaw.tokens.total",        "value": { "intValue": 94714 } }
        ],
        "status": { "code": 0 }
      }]
    }]
  }]
}
```

This produces one trace with one `model_call` span. `agent_id` is set to the `openclaw.sessionKey` value.

### Trace payload — message processed

```json
{
  "resourceSpans": [{
    "resource": {
      "attributes": [
        { "key": "service.name", "value": { "stringValue": "openclaw-gateway" } }
      ]
    },
    "scopeSpans": [{
      "spans": [{
        "traceId": "ea38f13d10ee63018411ecfd52a0c58c",
        "spanId": "ed6084907a79ccb4",
        "name": "openclaw.message.processed",
        "startTimeUnixNano": "1776353057352000000",
        "endTimeUnixNano":   "1776353064360000000",
        "attributes": [
          { "key": "openclaw.channel",    "value": { "stringValue": "discord" } },
          { "key": "openclaw.outcome",    "value": { "stringValue": "completed" } },
          { "key": "openclaw.sessionKey", "value": { "stringValue": "agent:main:discord:channel:1494326249361899544" } },
          { "key": "openclaw.chatId",     "value": { "stringValue": "channel:1494326249361899544" } },
          { "key": "openclaw.messageId",  "value": { "stringValue": "1494357773784453171" } }
        ],
        "status": { "code": 0 }
      }]
    }]
  }]
}
```

### Error span

A message that failed. Note that `status.code` is 0 — OpenClaw signals failure via `openclaw.outcome`, not the OTLP status code:

```json
{
  "traceId": "ea38f13d10ee63018411ecfd52a0c58c",
  "spanId": "ed6084907a79ccb4",
  "name": "openclaw.message.processed",
  "startTimeUnixNano": "1776353057352000000",
  "endTimeUnixNano":   "1776353064360000000",
  "attributes": [
    { "key": "openclaw.channel", "value": { "stringValue": "discord" } },
    { "key": "openclaw.outcome", "value": { "stringValue": "error" } },
    { "key": "openclaw.sessionKey", "value": { "stringValue": "agent:main:discord:channel:1494326249361899544" } }
  ],
  "status": { "code": 0 }
}
```

ClawTrace detects the `openclaw.outcome = "error"` attribute, sets `span_outcome = "error"`, and marks the trace status as `"error"`.

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
          "name": "openclaw.tokens",
          "sum": {
            "dataPoints": [{
              "startTimeUnixNano": "1776353064358000000",
              "asInt": 94714,
              "attributes": [
                { "key": "openclaw.channel", "value": { "stringValue": "discord" } }
              ]
            }]
          }
        },
        {
          "name": "openclaw.run.duration_ms",
          "histogram": {
            "dataPoints": [{
              "startTimeUnixNano": "1776353064358000000",
              "count": 1,
              "sum": 6746.0,
              "bucketCounts": [0, 0, 0, 1, 0],
              "explicitBounds": [1000, 3000, 5000, 10000],
              "attributes": [
                { "key": "openclaw.channel", "value": { "stringValue": "discord" } }
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
          "timeUnixNano": "1776353108071000000",
          "severityNumber": 9,
          "severityText": "INFO",
          "body": { "stringValue": "⇄ res ✓ agent.wait 45001ms" },
          "attributes": [
            { "key": "openclaw.subsystem", "value": { "stringValue": "gateway/ws" } },
            { "key": "openclaw.log.level", "value": { "stringValue": "INFO" } }
          ]
        },
        {
          "timeUnixNano": "1776353108632000000",
          "severityNumber": 13,
          "severityText": "WARN",
          "body": { "stringValue": "embedded run timeout: runId=21bae493 timeoutMs=45000" },
          "attributes": [
            { "key": "openclaw.subsystem", "value": { "stringValue": "agent/embedded" } },
            { "key": "openclaw.log.level", "value": { "stringValue": "WARN" } }
          ]
        }
      ]
    }]
  }]
}
```

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

**traceId is 32 chars, but ClawTrace shows 16**

ClawTrace truncates OTLP 32-char trace IDs to 16 chars for storage. This is intentional — the first 16 chars are used as the trace identifier throughout the UI.

**Agent shows as "unknown" on the Agents page**

`agent_id` is derived from span attributes, not resource attributes. Confirm that your spans include `openclaw.sessionKey` or `openclaw.chatId`. If neither is present, ClawTrace falls back to `service.name` from resource attributes, then to `"unknown"`.
