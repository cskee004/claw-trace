# OTLP Ingestion API

ClawTrace accepts OpenTelemetry Protocol (OTLP) trace payloads natively. OpenClaw users can point `diagnostics.otel.endpoint` directly at ClawTrace without a separate collector.

---

## Endpoint

```
POST /v1/traces
Content-Type: application/json
         or: application/x-protobuf
```

No authentication required — OTLP endpoints are unauthenticated by convention.

Both `application/json` (OTLP/JSON) and `application/x-protobuf` (OTLP/proto3) are accepted.

---

## Request

The body must be a JSON object conforming to the OTLP ResourceSpans format:

```json
{
  "resourceSpans": [
    {
      "resource": {
        "attributes": [
          { "key": "openclaw.session.key", "value": { "stringValue": "support-agent" } }
        ]
      },
      "scopeSpans": [
        {
          "spans": [
            {
              "traceId": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6",
              "spanId": "aaaa0000aaaa0000",
              "name": "openclaw.request",
              "startTimeUnixNano": "1712345678000000000",
              "attributes": []
            }
          ]
        }
      ]
    }
  ]
}
```

Only the first `resourceSpan` entry is processed. Multi-resource payloads are accepted without error — additional resources beyond the first are ignored.

---

## Responses

**200 OK** — always returned on success (per OTLP spec)

```json
{}
```

**200 OK** — also returned for empty or missing `resourceSpans` (no-op, nothing persisted)

**400 Bad Request** — malformed JSON body

```json
{ "error": "invalid JSON: ..." }
```

---

## agent_id Resolution

`agent_id` is read from the `openclaw.session.key` resource attribute. This must be one of the 8 valid agent types:

| Value |
|-------|
| `support-agent` |
| `research-agent` |
| `automation-agent` |
| `triage-agent` |
| `data-agent` |
| `monitoring-agent` |
| `code-agent` |
| `notification-agent` |

---

## Span Name → Span Type Mapping

OTLP span names are translated to ClawTrace span types by `OtlpNormalizer`:

| OTLP span name | ClawTrace span_type | Notes |
|----------------|---------------------|-------|
| `openclaw.request` | `agent_run_started` | |
| `openclaw.agent.turn` | `model_call` | |
| `tool.*` (any prefix match) | `tool_call` | e.g. `tool.web_search`, `tool.read_file` |
| `openclaw.command.*` (any prefix match) | `decision` | e.g. `openclaw.command.execute` |
| Any span with OTLP status code 2 | `error` | Overrides name-based mapping |
| The span with the highest timestamp | `run_completed` | Unless it has error status |
| Any other name | `model_call` | Fallback |

---

## OTLP Attribute Types

Span and resource attributes use OTLP's typed value format:

```json
{ "key": "prompt_tokens", "value": { "intValue": 1200 } }
```

Supported value types: `stringValue`, `intValue`, `doubleValue`, `boolValue`.

Span attributes are flattened into ClawTrace's `metadata` JSON column:
```json
{ "prompt_tokens": 1200, "model": "claude-sonnet-4-6" }
```

---

## Timestamp Conversion

OTLP timestamps are nanosecond Unix epoch strings and are converted to ISO 8601 millisecond precision:

```
"1712345678500000000"  →  "2024-04-05T22:54:38.500Z"
```

---

## Trace ID Normalization

OTLP trace IDs are 32-character hex strings. ClawTrace stores 16-character trace IDs, so the first 16 characters are used:

```
"a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"  →  "a1b2c3d4e5f6a7b8"
```

---

## OpenClaw Configuration

Point OpenClaw's OTLP exporter at ClawTrace:

```yaml
diagnostics:
  otel:
    endpoint: "http://localhost:3000/v1/traces"
```

For production, replace `localhost:3000` with your ClawTrace deployment URL.

---

## POST /v1/logs

```
POST /v1/logs
Content-Type: application/json
         or: application/x-protobuf
```

No authentication required — OTLP endpoints are unauthenticated by convention.

Both `application/json` (OTLP/JSON) and `application/x-protobuf` (OTLP/proto3) are accepted.

### Request

The body must conform to the OTLP `ExportLogsServiceRequest` format:

```json
{
  "resourceLogs": [
    {
      "resource": {
        "attributes": []
      },
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
                { "key": "service.name", "value": { "stringValue": "openclaw" } }
              ]
            }
          ]
        }
      ]
    }
  ]
}
```

All fields are optional — log records without `traceId` or `spanId` are accepted and stored.

### Responses

**200 OK** — always returned on success (per OTLP spec)

```json
{}
```

**200 OK** — also returned for empty or missing `resourceLogs` (no-op, nothing persisted)

**400 Bad Request** — malformed JSON or malformed protobuf

```json
{ "error": "..." }
```

### Correlation

`traceId` and `spanId` in the log record correlate logs to traces and spans in ClawTrace. Both are optional — logs are stored without them. No DB-level foreign key is enforced; logs may arrive before or without a corresponding trace.

### Log Attributes

Log record attributes use the same OTLP typed value format as span attributes:

```json
{ "key": "service.name", "value": { "stringValue": "openclaw" } }
```

Supported value types: `stringValue`, `intValue`, `doubleValue`, `boolValue`.

Attributes are flattened and stored in the `log_attributes` JSON column.

### OpenClaw Configuration

Point OpenClaw's OTLP logs exporter at ClawTrace:

```yaml
diagnostics:
  otel:
    logs_endpoint: "http://localhost:3000/v1/logs"
```

For production, replace `localhost:3000` with your ClawTrace deployment URL.
