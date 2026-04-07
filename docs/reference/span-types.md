# Span Types Reference

Spans are the atomic units of a trace. Each span represents one step in an agent execution. The `span_type` field constrains what a span means and what metadata shape it carries.

## Canonical Span Types

Eight span types are recognized. Any other value is rejected at ingestion.

| Type | Role | Fires When |
|------|------|------------|
| `agent_run_started` | Root span — opens the trace | Agent begins executing a task |
| `model_call` | LLM invocation begins | Prompt is dispatched to the model |
| `model_response` | LLM response received | Model returns a completion |
| `tool_call` | Tool invocation begins | Agent calls an external tool |
| `tool_result` | Tool response received | Tool returns its result |
| `decision` | Agent reasoning step | Agent evaluates output and chooses next action |
| `error` | Failure event | An error occurs during execution |
| `run_completed` | Terminal span — closes the trace | Execution finishes (success or error) |

---

## Span Tree

A typical 7-step trace follows this parent–child topology:

```
agent_run_started (s1, root)
├── model_call (s2)
│   └── model_response (s3)
│       ├── tool_call (s4)
│       │   └── tool_result (s5)
│       └── decision (s6)
└── run_completed (s7)
```

On failure, an `error` span may appear before `run_completed`:

```
agent_run_started (s1, root)
├── model_call (s2)
│   └── model_response (s3)
│       ├── tool_call (s4)
│       │   └── tool_result (s5)
│       └── decision (s6)
│           └── error (s8)
└── run_completed (s7, status=error)
```

---

## Per-Type Details

### `agent_run_started`
The root span. Every trace must have exactly one. Always has `parent_span_id: null`.

### `model_call`
Signals the beginning of an LLM invocation. Carries token budget and model configuration in metadata.

### `model_response`
Signals the LLM returned a result. Carries token counts and the completion stop reason.

### `tool_call`
Signals a tool was invoked. Carries the tool name and its input arguments.

### `tool_result`
Signals a tool returned. The `success` metadata field is semantically significant — `ToolCallAnalyzer` uses it to compute per-tool success rates.

### `decision`
Represents the agent's reasoning step after receiving tool output or model response. Carries the chosen action and confidence score.

### `error`
Injected when an agent run fails. Carries an error message and machine-readable error code. A trace is considered "errored" by `ErrorRateAnalyzer` if it contains at least one span of this type.

### `run_completed`
Always the last span in a trace. Its `metadata.status` reflects the overall outcome (`"success"` or `"error"`).

---

## Metadata Schemas

See [metadata-schemas.md](metadata-schemas.md) for the expected metadata shape for each span type.

---

## Extending Span Types

Adding a new span type requires:
1. Add the value to `Span::SPAN_TYPES` in `app/models/span.rb`
2. Update `OtlpNormalizer#map_span_name` in `app/lib/otlp_normalizer.rb` if it has a distinct OTLP name
3. Document the expected metadata shape in `docs/reference/metadata-schemas.md`
