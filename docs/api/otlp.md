# OTLP Ingestion API

ClawTrace accepts OpenTelemetry Protocol (OTLP) traces, metrics, and logs over HTTP.

**Recommended integration:** Use the [`@clawtrace-io/clawtails`](../openclaw-plugin.md) OpenClaw plugin. It instruments your agent automatically and produces the full waterfall view — agent turns, tool calls, token usage, and correlated logs — with a single install command:

```bash
openclaw plugins install @clawtrace-io/clawtails
```

**Alternative:** Point OpenClaw's built-in OTLP diagnostics at ClawTrace for flat span ingestion (compact single-span card view, no waterfall hierarchy):

```json
{
  "diagnostics": {
    "otel": {
      "enabled": true,
      "endpoint": "http://localhost:3000"
    }
  }
}
```

---

## Endpoints

All endpoints are unauthenticated — OTLP convention. All return `{}` with HTTP 200 on success.

```
POST /v1/traces    Content-Type: application/json | application/x-protobuf
POST /v1/metrics   Content-Type: application/json | application/x-protobuf
POST /v1/logs      Content-Type: application/json | application/x-protobuf
```

---

## POST /v1/traces

### Request

Body must be a valid OTLP `ExportTraceServiceRequest` (ResourceSpans format):

```json
{
  "resourceSpans": [
    {
      "resource": {
        "attributes": [
          { "key": "service.name", "value": { "stringValue": "openclaw-gateway" } }
        ]
      },
      "scopeSpans": [
        {
          "spans": [
            {
              "traceId": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6",
              "spanId": "aaaa0000aaaa0000",
              "parentSpanId": "",
              "name": "openclaw.request",
              "startTimeUnixNano": "1712345678000000000",
              "endTimeUnixNano": "1712345679500000000",
              "status": { "code": 0 },
              "attributes": [
                { "key": "openclaw.sessionKey", "value": { "stringValue": "my-agent" } }
              ]
            }
          ]
        }
      ]
    }
  ]
}
```

All `resourceSpans` entries are processed. Multi-service payloads (one entry per service) are supported — spans from every entry are aggregated by `traceId`. Each entry's `agent_id` is resolved independently from its own resource and span attributes.

### Responses

**200 OK** — success (per OTLP spec):
```json
{}
```

**200 OK** — empty or missing `resourceSpans` — no-op, nothing persisted.

**400 Bad Request** — malformed JSON:
```json
{ "error": "invalid JSON: ..." }
```

**400 Bad Request** — malformed protobuf:
```json
{ "error": "truncated protobuf message" }
```

---

## Span Name → Span Type Mapping

OTLP span names are mapped to ClawTrace `span_type` values by `OtlpNormalizer`. Rules are evaluated **in order** — first prefix match wins:

| OTLP span name prefix | ClawTrace `span_type` | Example span name |
|-----------------------|-----------------------|-------------------|
| `openclaw.model.`     | `model_call`          | `openclaw.model.response` |
| `openclaw.message.`   | `message_event`       | `openclaw.message.received` |
| `openclaw.session.`   | `session_event`       | `openclaw.session.start` |
| `openclaw.command.`   | `command_event`       | `openclaw.command.execute` |
| `openclaw.webhook.`   | `webhook_event`       | `openclaw.webhook.received` |
| `openclaw.tool.`      | `tool_call`           | `openclaw.tool.bash` |
| `openclaw.request`    | `agent_request`       | `openclaw.request` |
| `openclaw.agent.`     | `agent_turn`          | `openclaw.agent.turn` |
| `openclaw.`           | `openclaw_event`      | `openclaw.context.compaction` |
| `tool.`               | `tool_call`           | `tool.Read`, `tool.exec` |
| *(anything else)*     | `span`                | — |

The `clawtails` plugin emits `openclaw.request`, `openclaw.agent.turn`, and `openclaw.tool.<name>` spans, which resolve to `agent_request`, `agent_turn`, and `tool_call` respectively.

---

## agent_id Resolution

ClawTrace derives `agent_id` for each span using a first-match chain. Span attributes take priority over resource attributes:

1. `openclaw.sessionKey` span attribute
2. `openclaw.chatId` span attribute
3. `service.name` resource attribute
4. `"unknown"` (fallback)

The `clawtails` plugin sets `openclaw.sessionKey` on every span it emits.

---

## Span Outcome

`span_outcome` is derived from the `openclaw.outcome` span attribute or OTLP status:

- OTLP status `code: 2` → `"error"` (overrides `openclaw.outcome`)
- `openclaw.outcome` in `["error", "failed", "timeout", "timed_out"]` → `"error"`
- Any other `openclaw.outcome` value → stored as-is (e.g. `"success"`)
- No `openclaw.outcome` and no error status → `nil`

Trace `status` is `"error"` if any span in the trace has an error outcome; otherwise `"success"`.

---

## Token Attributes

Token counts are read from span attributes. Both conventions are accepted — ClawTrace checks `openclaw.tokens.*` first, then falls back to OTel Semantic Conventions (`gen_ai.usage.*`):

| ClawTrace column          | Primary key                      | Fallback key                        |
|---------------------------|----------------------------------|-------------------------------------|
| `span_input_tokens`       | `openclaw.tokens.input`          | `gen_ai.usage.input_tokens`         |
| `span_output_tokens`      | `openclaw.tokens.output`         | `gen_ai.usage.output_tokens`        |
| `span_cache_read_tokens`  | `openclaw.tokens.cache_read`     | `gen_ai.usage.cache_read_tokens`    |
| `span_cache_write_tokens` | `openclaw.tokens.cache_write`    | `gen_ai.usage.cache_write_tokens`   |
| `span_total_tokens`       | `openclaw.tokens.total`          | `gen_ai.usage.total_tokens`         |

`span_model` is read from `openclaw.model`. `span_provider` from `openclaw.provider`.

The `clawtails` plugin emits `gen_ai.usage.*` attributes (OTel Semantic Conventions). The built-in OpenClaw OTLP diagnostics emit `openclaw.tokens.*`.

---

## OTLP Attribute Types

Span and resource attributes use OTLP's typed value format:

```json
{ "key": "openclaw.tokens.input", "value": { "intValue": 1200 } }
```

Supported value types: `stringValue`, `intValue`, `doubleValue`, `boolValue`.

Attributes are flattened into the `metadata` JSON column:
```json
{ "openclaw.tokens.input": 1200, "openclaw.model": "claude-sonnet-4-6" }
```

Non-scalar types (`arrayValue`, `kvlistValue`, `bytesValue`) are omitted.

---

## Timestamp Conversion

OTLP timestamps are nanosecond Unix epoch strings, converted to ISO 8601 millisecond precision:

```
"1712345678500000000"  →  "2024-04-05T22:54:38.500Z"
```

---

## Trace ID Normalization

OTLP trace IDs are 32-character hex strings. ClawTrace stores 16-character trace IDs — the first 16 characters are used:

```
"a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"  →  "a1b2c3d4e5f6a7b8"
```

The `clawtails` plugin generates 32-char trace IDs via `crypto.randomBytes(16).toString('hex')` — ClawTrace truncates on ingestion.

---

## POST /v1/logs

### Request

Body must conform to the OTLP `ExportLogsServiceRequest` format:

```json
{
  "resourceLogs": [
    {
      "resource": {},
      "scopeLogs": [
        {
          "logRecords": [
            {
              "timeUnixNano": "1712345678500000000",
              "severityText": "INFO",
              "severityNumber": 9,
              "body": { "stringValue": "agent turn completed" },
              "traceId": "a1b2c3d4e5f6a7b8",
              "spanId": "ab12cd34ef56a1b2",
              "attributes": [
                { "key": "openclaw.subsystem", "value": { "stringValue": "agent_turn" } }
              ]
            }
          ]
        }
      ]
    }
  ]
}
```

All fields are optional. Log records without `traceId` or `spanId` are stored unlinked.

### Responses

**200 OK** — success: `{}`

**200 OK** — empty or missing `resourceLogs` — no-op.

**400 Bad Request** — malformed JSON or protobuf: `{ "error": "..." }`

### Correlation

`traceId` in log records must be 16 characters (already truncated to match ClawTrace's stored trace IDs). The `clawtails` plugin handles this automatically. No DB-level foreign key is enforced — logs may arrive before or without a corresponding trace.

Log attributes are flattened using the same OTLP typed value format as span attributes, stored in `log_attributes`.

---

## POST /v1/metrics

### Request

Body must conform to the OTLP `ExportMetricsServiceRequest` format (ResourceMetrics). Sum and gauge metric types are aggregated into rolling totals — one row per `metric_key`, updated on each ingestion. Histogram data points are silently dropped.

### Responses

**200 OK** — success: `{}`

**400 Bad Request** — malformed input: `{ "error": "..." }`
