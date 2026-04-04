# Simulator

`simulator/`

Generates realistic synthetic agent telemetry without a live agent. Used for development seeding, testing, and end-to-end validation of the ingestion pipeline.

> **Important:** `Simulator::Trace` is an immutable value object defined in `simulator/trace_generator.rb`. `Trace` (no namespace) is the ActiveRecord model in `app/models/`. Do not conflate them.

---

## Components

### `TelemetryEvent` — `simulator/telemetry_event.rb`

Immutable value object (`Data.define`) representing a single span event.

```ruby
event = TelemetryEvent.build(
  trace_id:       "a1b2c3d4e5f60708",
  span_id:        "s1",
  span_type:      "agent_run_started",
  timestamp:      "2026-04-04T10:00:00Z",
  agent_id:       "support-agent",
  metadata:       { "task" => "classify_customer_ticket" },
  parent_span_id: nil   # optional
)

event.to_json  # => JSON string
```

`.build` validates `span_type` against `SPAN_TYPES` and raises `ArgumentError` for unknown values. Defines `SPAN_TYPES` and `METADATA_SCHEMA` — these are the canonical constants for the entire system.

---

### `TraceGenerator` — `simulator/trace_generator.rb`

Generates `Simulator::Trace` value objects with randomized but realistic metadata.

```ruby
gen = TraceGenerator.new(seed: 42)
trace = gen.generate
# => Simulator::Trace(trace_id: "a1b2...", agent_id: "support-agent",
#                     task_name: "classify_customer_ticket",
#                     start_time: "2026-04-04T10:00:00Z", status: "in_progress")
```

Generates traces with `status: "in_progress"`. `AgentSimulator` is responsible for finalizing status to `"success"` or `"error"` after simulating the run.

**Agent types and task pools:**

| Agent Type | Task Names |
|------------|------------|
| `support-agent` | classify_customer_ticket, resolve_billing_dispute, escalate_to_human |
| `research-agent` | summarize_research_paper, find_competitor_pricing, extract_key_findings |
| `automation-agent` | sync_crm_records, send_follow_up_emails, generate_weekly_report |
| `triage-agent` | prioritize_incident_queue, route_support_ticket, assess_severity_level |
| `data-agent` | analyze_sales_trends, generate_forecast_report, clean_dataset |
| `monitoring-agent` | check_service_health, detect_anomaly, alert_on_threshold |
| `code-agent` | review_pull_request, generate_unit_tests, refactor_module |
| `notification-agent` | send_status_update, broadcast_incident_alert, notify_stakeholders |

---

### `SpanGenerator` — `simulator/span_generator.rb`

Generates ordered `TelemetryEvent` arrays following the 7-step canonical sequence.

```ruby
gen = SpanGenerator.new(seed: 42)
spans = gen.generate_sequence(trace: trace)
# => Array of 7 TelemetryEvent objects (agent_run_started through run_completed)
```

Timestamps advance from `trace.start_time` by a random 5–500ms per span. Span IDs are sequential: `"s1"` through `"s7"`.

`generate_single` produces an arbitrary span outside the default sequence — used internally by `AgentSimulator` to inject error spans:

```ruby
gen.generate_single(
  span_type:      "error",
  trace:          trace,
  span_id:        "s8",
  parent_span_id: "s6"
)
```

For the span tree structure, see [span-types.md](../reference/span-types.md).

---

### `AgentSimulator` — `simulator/agent_simulator.rb`

Orchestrates `TraceGenerator` and `SpanGenerator` to produce complete simulated runs.

**15% failure rate** by default: on failure, an `error` span (`s8`, parented to `s6`) is injected between `decision` and `run_completed`, and the trace status is finalized to `"error"`.

**Seed propagation:** The master seed derives independent child seeds for `TraceGenerator` and `SpanGenerator` so their random streams don't interfere.

```ruby
sim = AgentSimulator.new(seed: 42)

# Returns a SimulatedRun value object
run = sim.run
run.trace   # => Simulator::Trace (finalized, status = "success" or "error")
run.spans   # => Array<TelemetryEvent>

# Returns NDJSON string ready for TelemetryIngester
ndjson = sim.emit
```

---

## Usage

### Generate NDJSON for the API

```ruby
ndjson = AgentSimulator.new.emit
# POST this to /api/v1/telemetry as the raw body
```

### Reproducible output (tests)

```ruby
# Always use a fixed seed in specs
ndjson = AgentSimulator.new(seed: 42).emit
```

### Seed the database directly

```ruby
result = SimulatorSeeder.call(count: 10)
result.traces_created  # => 10
result.errors          # => []
```

`SimulatorSeeder` calls `AgentSimulator` for each trace and pipes the output through `TelemetryIngester`. Individual failures are collected in `result.errors` — a single bad trace does not abort the run.

### Seed via web UI

```
POST /traces/seed
```

Calls `SimulatorSeeder.call` and redirects to the trace list with a flash message.

---

## Seed vs. No Seed

Always use a fixed seed in tests. Without a seed, all simulator classes use `Random.new` (non-deterministic):

```ruby
# Tests — always deterministic
AgentSimulator.new(seed: 42).emit

# Development — randomized each run
AgentSimulator.new.emit
```

All four simulator classes (`TraceGenerator`, `SpanGenerator`, `AgentSimulator`, and the child RNGs) use `Random.new(seed)` — passing a seed at the top level propagates through the entire chain.
