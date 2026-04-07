# TelemetryIngester

`app/lib/telemetry_ingester.rb`

Persists telemetry data to the database as `Trace` + `Span` records. All writes are atomic — the full payload succeeds or nothing is stored.

---

## Interface

```ruby
result = TelemetryIngester.call(trace: trace_hash, spans: span_array)
# => { trace_id: "a1b2c3d4e5f60708", spans_ingested: 4 }
```

`.call` is a class-method shorthand that creates an instance and calls `#call`.

---

## Input

**`trace:`** — a Hash with string keys:

| Key | Type | Description |
|-----|------|-------------|
| `"trace_id"` | String | 16-char hex trace identifier |
| `"agent_id"` | String | Agent type (e.g. `"support-agent"`) |
| `"task_name"` | String | Human-readable task description |
| `"start_time"` | String | ISO 8601 timestamp |
| `"status"` | String | `"success"`, `"error"`, or `"in_progress"` (default) |

**`spans:`** — an Array of Hashes, each with string keys:

| Key | Type | Description |
|-----|------|-------------|
| `"span_id"` | String | Unique span identifier |
| `"parent_span_id"` | String \| nil | Parent span ID, or nil for root spans |
| `"span_type"` | String | One of the defined span types |
| `"timestamp"` | String | ISO 8601 timestamp |
| `"agent_id"` | String | Agent type |
| `"metadata"` | Hash | Arbitrary key-value pairs |

An empty `spans:` array is valid — only the trace record is persisted.

---

## Output

Returns a plain Ruby hash:

```ruby
{
  trace_id:       "a1b2c3d4e5f60708",  # String — the stored trace ID
  spans_ingested: 4                     # Integer — number of span rows created
}
```

---

## Error Handling

Raises `TelemetryIngester::Error` (a subclass of `StandardError`) for:

| Scenario | Error message |
|----------|---------------|
| `trace:` is nil or not a Hash | `"trace is missing or invalid"` |
| `spans:` is nil or not an Array | `"spans must be an array"` |
| Model validation failure | `"Validation failed: ..."` (wrapped `ActiveRecord::RecordInvalid`) |

```ruby
begin
  result = TelemetryIngester.call(trace: trace_hash, spans: span_array)
rescue TelemetryIngester::Error => e
  # e.message contains the specific failure reason
end
```

---

## Transaction Semantics

All database writes (one `Trace` + N `Span` records) are wrapped in a single `ActiveRecord::Base.transaction`. If any record fails to save, all writes are rolled back.

---

## Usage in Controllers

```ruby
# app/controllers/api/v1/telemetry_controller.rb — Bearer token API
lines = request.raw_post.split("\n").map(&:strip).reject(&:empty?)
trace_data, *span_data = lines.map { |l| JSON.parse(l) }
result = TelemetryIngester.call(trace: trace_data, spans: span_data)

# app/controllers/api/v1/otlp_controller.rb — OTLP path
result = OtlpNormalizer.call(request.raw_post)
TelemetryIngester.call(**result)
```

---

## Usage in Tests

```ruby
result = TelemetryIngester.call(
  trace: {
    "trace_id"   => "a1b2c3d4e5f6a7b8",
    "agent_id"   => "support-agent",
    "task_name"  => "classify_customer_ticket",
    "start_time" => "2026-04-02T12:00:00Z",
    "status"     => "success"
  },
  spans: [
    {
      "span_id"        => "s1",
      "parent_span_id" => nil,
      "span_type"      => "agent_run_started",
      "timestamp"      => "2026-04-02T12:00:01Z",
      "agent_id"       => "support-agent",
      "metadata"       => {}
    }
  ]
)

expect(result[:spans_ingested]).to eq(1)
expect(Trace.find_by(trace_id: result[:trace_id])).to be_present
```
