# Span Metadata Schemas

The `metadata` column is a JSON object whose shape varies by `span_type`. The application never fails if optional fields are absent — metadata is always treated as best-effort.

For span type definitions and the span tree, see [span-types.md](span-types.md).

---

## `agent_run_started`

```json
{
  "task": "classify_customer_ticket"
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `task` | string | yes | The task name the agent was asked to complete |

---

## `model_call`

```json
{
  "model_name": "claude-sonnet-4-6",
  "prompt_tokens": 1200,
  "latency_ms": 2100,
  "temperature": 0.7
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `model_name` | string | yes | Model identifier (e.g. `"claude-sonnet-4-6"`, `"gpt-4o"`) |
| `prompt_tokens` | integer | yes | Number of tokens in the prompt |
| `latency_ms` | integer | no | Time to first token in milliseconds |
| `temperature` | float | no | Sampling temperature used for this call |

---

## `model_response`

```json
{
  "completion_tokens": 340,
  "output_preview": "Processing: classify_customer_ticket",
  "stop_reason": "end_turn"
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `completion_tokens` | integer | yes | Tokens in the model's completion |
| `output_preview` | string | no | Truncated preview of the model output |
| `stop_reason` | string | no | One of `"end_turn"`, `"max_tokens"`, `"stop_sequence"` |

---

## `tool_call`

```json
{
  "tool_name": "search",
  "arguments": {
    "query": "classify_customer_ticket",
    "max_results": 5
  }
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `tool_name` | string | yes | Name of the tool being invoked |
| `arguments` | object | yes | Tool-specific input arguments |

**Known tool names:** `search`, `lookup`, `fetch`, `write`, `classify`, `summarize`

---

## `tool_result`

```json
{
  "tool_name": "search",
  "success": true,
  "result": "ok",
  "latency_ms": 120
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `tool_name` | string | yes | Name of the tool that responded |
| `success` | boolean | yes | **Semantically significant** — used by `ToolCallAnalyzer` to compute success rates |
| `result` | string | no | One of `"ok"`, `"not_found"`, `"partial"`, `"error"`, `"timeout"` |
| `latency_ms` | integer | no | Tool execution time in milliseconds |

> `ToolCallAnalyzer` reads `metadata["tool_name"]` and `metadata["success"]` from `tool_result` spans. If either is absent the span is excluded from statistics.

---

## `decision`

```json
{
  "action": "escalate",
  "confidence": 0.87,
  "reasoning": "Escalating due to low confidence score"
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `action` | string | yes | One of `"escalate"`, `"retry"`, `"complete"`, `"skip"`, `"delegate"` |
| `confidence` | float | yes | Confidence score (0.0–1.0) |
| `reasoning` | string | no | Human-readable explanation of the decision |

---

## `error`

```json
{
  "message": "Request timed out after 30s",
  "code": "TIMEOUT"
}
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `message` | string | yes | Human-readable error description |
| `code` | string | yes | Machine-readable error code |

**Known error codes:** `TIMEOUT`, `NOT_FOUND`, `RATE_LIMITED`, `INVALID_INPUT`, `UNKNOWN`

> A trace is counted as errored by `ErrorRateAnalyzer` if it contains at least one span with `span_type == "error"`. The `metadata` contents are not inspected.

---

## `run_completed`

```json
{ "status": "success" }
```

or, on failure:

```json
{ "status": "error" }
```

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `status` | string | yes | `"success"` or `"error"` — mirrors the parent trace's status |

---

## Optional Fields and OTLP

When traces are ingested via the OTLP path (OpenClaw), metadata is populated from flattened OTLP attributes. Additional optional fields such as `cost_usd`, cache token counts, and context window details may appear. These fields are never required and never cause ingestion failures if absent.

OTLP ingestion documentation will be added once the OTLP endpoint is implemented.
