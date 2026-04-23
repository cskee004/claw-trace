# Database Schema

ClawTrace uses six tables. Two store telemetry data (`traces`, `spans`); one stores OTLP log records (`logs`); one stores OTLP metrics (`metrics`); one stores per-agent spend limits (`agent_budgets`); one stores application settings (`settings`).

**Relationship:** `spans.trace_id` is a string foreign key referencing `traces.trace_id` — not the integer `id`. Rails URL helpers use `trace_id` via `Trace#to_param`.

---

## `traces`

One row per agent execution run.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | integer | PK, auto-increment | Internal row ID — not used in URLs or API responses |
| `trace_id` | string | NOT NULL, unique | 16-char lowercase hex, e.g. `"a1b2c3d4e5f60708"` |
| `agent_id` | string | NOT NULL | Must be one of the 8 valid agent types |
| `task_name` | string | NOT NULL | Human-readable task description |
| `start_time` | datetime | NOT NULL | ISO 8601 UTC timestamp of when the run began |
| `status` | integer | NOT NULL, default 0 | Enum: `0=in_progress`, `1=success`, `2=error` |
| `created_at` | datetime | NOT NULL | Rails timestamp |
| `updated_at` | datetime | NOT NULL | Rails timestamp |

**Indexes:** `trace_id` (unique), `agent_id`, `start_time`, `status`

---

## `spans`

One row per span event within a trace.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | integer | PK, auto-increment | Internal row ID |
| `trace_id` | string | NOT NULL, FK → traces.trace_id | Groups spans into their parent trace |
| `span_id` | string | NOT NULL | Unique within a trace (e.g. `"s1"`, `"s2"`) |
| `parent_span_id` | string | nullable | References another span's `span_id`; null on root spans |
| `span_type` | string | NOT NULL | Must be one of the 8 canonical types |
| `timestamp` | datetime | NOT NULL | ISO 8601 UTC timestamp when this span fired |
| `agent_id` | string | NOT NULL | Agent that emitted this span |
| `metadata` | JSON | NOT NULL, default `{}` | Shape varies by `span_type` — see [metadata-schemas.md](metadata-schemas.md) |
| `end_time` | datetime | nullable | ISO 8601 UTC timestamp when this span ended |
| `span_name` | string | nullable | OTLP span operation name (e.g. `"agent.turn.process"`, `"llm.inference"`); null for Bearer-token-ingested spans |
| `span_model` | string | nullable | LLM model identifier (e.g. `"claude-sonnet-4-6"`); set only on model-call spans |
| `span_provider` | string | nullable | LLM provider (e.g. `"anthropic"`, `"openai"`); set only on model-call spans |
| `span_input_tokens` | integer | nullable | Prompt token count; set only on model-call spans |
| `span_output_tokens` | integer | nullable | Completion token count; set only on model-call spans |
| `span_cache_read_tokens` | integer | nullable | Cache-read token count (Anthropic prompt caching) |
| `span_cache_write_tokens` | integer | nullable | Cache-write token count (Anthropic prompt caching) |
| `span_total_tokens` | integer | nullable | Total tokens (input + output); set only on model-call spans |
| `span_outcome` | string | nullable | Outcome label (e.g. `"success"`, `"error"`) |
| `span_cost_usd` | decimal(10,8) | nullable | Estimated USD cost for this span; computed by `ModelPricingService` at ingestion time |
| `created_at` | datetime | NOT NULL | Rails timestamp |
| `updated_at` | datetime | NOT NULL | Rails timestamp |

**Indexes:** `(trace_id, span_id)` composite unique, `trace_id`, `agent_id`, `span_type`, `parent_span_id`

---

## `metrics`

One row per OTLP metric data point.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | integer | PK, auto-increment | Internal row ID |
| `trace_id` | string | nullable, indexed | Links to a trace if present in the resource attributes |
| `metric_name` | string | NOT NULL, indexed | e.g. `"gen_ai.client.token.usage"` |
| `metric_type` | string | NOT NULL | `"sum"` or `"histogram"` |
| `metric_attributes` | JSON | NOT NULL, default `{}` | Flattened OTLP data point attributes (model, provider, channel, etc.) |
| `data_points` | JSON | NOT NULL, default `{}` | Type-specific: sum `{ value, start_time }`; histogram `{ count, sum, min, max, bucket_counts, explicit_bounds }` |
| `timestamp` | datetime | NOT NULL, indexed | Converted from `timeUnixNano` |
| `created_at` | datetime | NOT NULL | Rails timestamp |

**Indexes:** `trace_id`, `metric_name`, `timestamp`

> **Note:** The column is `metric_attributes` (not `attributes`) because ActiveRecord reserves the `attributes` method name.

---

## `logs`

One row per OTLP log record.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | integer | PK, auto-increment | Internal row ID |
| `trace_id` | string | nullable, indexed | Correlates to a trace when present; logs may arrive without a trace |
| `span_id` | string | nullable, indexed | Correlates to a span when present |
| `severity_text` | string | nullable | Human-readable severity label (e.g. `"INFO"`, `"WARN"`, `"ERROR"`) |
| `severity_number` | integer | nullable | OTLP numeric severity level (1–24); nil when absent |
| `body` | text | nullable | Log message body; nil when absent |
| `log_attributes` | JSON | NOT NULL, default `{}` | Flattened OTLP log record attributes |
| `timestamp` | datetime | NOT NULL, indexed | Converted from `timeUnixNano` |
| `created_at` | datetime | NOT NULL | Rails timestamp |
| `updated_at` | datetime | NOT NULL | Rails timestamp |

**Indexes:** `trace_id`, `span_id`, `timestamp`

> **Note:** No DB-level foreign key on `trace_id` — logs may arrive before or without a corresponding trace. The `Log` model uses `belongs_to :trace, optional: true` for optional in-memory association.

> **Note:** The column is `log_attributes` (not `attributes`) because ActiveRecord reserves the `attributes` method name.

---

## `agent_budgets`

One row per agent that has a daily spend limit configured.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | integer | PK, auto-increment | Internal row ID |
| `agent_id` | string | NOT NULL, unique | Agent identifier matching `spans.agent_id` (e.g. `"support-agent"`) |
| `daily_limit_usd` | decimal(10,4) | NOT NULL | Daily spend ceiling in US dollars |
| `created_at` | datetime | NOT NULL | Rails timestamp |
| `updated_at` | datetime | NOT NULL | Rails timestamp |

**Indexes:** `agent_id` (unique)

> Managed via the Agent show page. `BudgetChecker.check` reads this table when evaluating daily spend across all configured agents.

---

## `settings`

Key-value store for application-level configuration.

| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| `id` | integer | PK, auto-increment | Internal row ID |
| `key` | string | NOT NULL, unique | Setting name |
| `value` | text | nullable | Setting value |

**Indexes:** `key` (unique)

---

## Foreign Key

```sql
ALTER TABLE spans ADD FOREIGN KEY (trace_id) REFERENCES traces(trace_id);
```

The FK references `traces.trace_id` (string), not `traces.id` (integer). This is intentional — trace IDs are stable identifiers generated at ingestion time and used throughout the API.

---

## Design Notes

- **`trace_id` is the public identifier.** `Trace#to_param` returns `trace_id`, so all URLs are `/traces/a1b2c3d4e5f60708` rather than `/traces/1`.
- **`metadata` is a schemaless JSON column.** The application never fails if optional fields are absent. See [metadata-schemas.md](metadata-schemas.md) for expected shapes.
- **`status` is stored as an integer enum.** Rails maps `in_progress: 0`, `success: 1`, `error: 2`. Migrations must not change these ordinal values.
