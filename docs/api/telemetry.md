# Telemetry Ingestion API

## Endpoint

```
POST /api/v1/telemetry
Authorization: Bearer <token>
```

Accepts a complete agent execution trace as NDJSON (newline-delimited JSON). All records are written atomically — either the full trace is stored or nothing is.

---

## NDJSON Format

The body is plain text with one JSON object per line:

- **Line 1:** trace record
- **Lines 2+:** span records (at least one required)

**Content-Type:** `text/plain` (raw POST body — no `application/json` wrapper)

---

## Trace Record (Line 1)

```json
{
  "trace_id": "a1b2c3d4e5f60708",
  "agent_id": "support-agent",
  "task_name": "classify_customer_ticket",
  "start_time": "2026-04-04T10:00:00Z",
  "status": "success"
}
```

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| `trace_id` | string | yes | Exactly 16 lowercase hex characters |
| `agent_id` | string | yes | Must be one of the 8 valid agent types |
| `task_name` | string | yes | Human-readable task description |
| `start_time` | string | yes | ISO 8601 UTC datetime |
| `status` | string | no | `"in_progress"`, `"success"`, or `"error"` — defaults to `"in_progress"` |

---

## Span Record (Lines 2+)

```json
{
  "trace_id": "a1b2c3d4e5f60708",
  "span_id": "s1",
  "parent_span_id": null,
  "span_type": "agent_run_started",
  "timestamp": "2026-04-04T10:00:00.123Z",
  "agent_id": "support-agent",
  "metadata": { "task": "classify_customer_ticket" }
}
```

| Field | Type | Required | Constraints |
|-------|------|----------|-------------|
| `trace_id` | string | yes | Must match the trace record's `trace_id` |
| `span_id` | string | yes | Unique within the trace |
| `parent_span_id` | string\|null | no | References another span's `span_id`; null for root spans |
| `span_type` | string | yes | Must be one of the 8 canonical types |
| `timestamp` | string | yes | ISO 8601 UTC datetime |
| `agent_id` | string | yes | Must be one of the 8 valid agent types |
| `metadata` | object | no | Shape varies by `span_type` — see [metadata-schemas.md](../reference/metadata-schemas.md) |

---

## Full Example

```
{"trace_id":"a1b2c3d4e5f60708","agent_id":"support-agent","task_name":"classify_customer_ticket","start_time":"2026-04-04T10:00:00Z","status":"success"}
{"trace_id":"a1b2c3d4e5f60708","span_id":"s1","parent_span_id":null,"span_type":"agent_run_started","timestamp":"2026-04-04T10:00:00.050Z","agent_id":"support-agent","metadata":{"task":"classify_customer_ticket"}}
{"trace_id":"a1b2c3d4e5f60708","span_id":"s2","parent_span_id":"s1","span_type":"model_call","timestamp":"2026-04-04T10:00:00.300Z","agent_id":"support-agent","metadata":{"model_name":"claude-sonnet-4-6","prompt_tokens":1200}}
{"trace_id":"a1b2c3d4e5f60708","span_id":"s7","parent_span_id":"s1","span_type":"run_completed","timestamp":"2026-04-04T10:00:03.100Z","agent_id":"support-agent","metadata":{"status":"success"}}
```

---

## Responses

**201 Created**

```json
{
  "trace_id": "a1b2c3d4e5f60708",
  "spans_ingested": 4
}
```

**401 Unauthorized** — missing or invalid Bearer token

```json
{ "error": "unauthorized" }
```

**422 Unprocessable Entity** — malformed NDJSON, validation failure, or duplicate trace

```json
{ "error": "Validation failed: trace_id has already been taken" }
```

---

## Validation Rules

- Payload must not be empty
- At least one span record is required
- `trace_id` must be exactly 16 characters
- `agent_id` must be one of: `support-agent`, `research-agent`, `automation-agent`, `triage-agent`, `data-agent`, `monitoring-agent`, `code-agent`, `notification-agent`
- `span_type` must be one of the 8 canonical types (see [span-types.md](../reference/span-types.md))
- Each `(trace_id, span_id)` pair must be unique across the database
- All writes are wrapped in a single transaction — if any record fails validation, the entire payload is rolled back

---

## Valid `agent_id` Values

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
