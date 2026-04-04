# TelemetryIngester

`app/lib/telemetry_ingester.rb`

Parses NDJSON telemetry payloads and persists them to the database as `Trace` + `Span` records. All writes are atomic — the full payload succeeds or nothing is stored.

---

## Interface

```ruby
result = TelemetryIngester.call(ndjson_string)
# => { trace_id: "a1b2c3d4e5f60708", spans_ingested: 4 }
```

`.call` is a class-method shorthand that creates an instance and calls `#call`.

---

## Input Format

NDJSON — one JSON object per line (matches `AgentSimulator#emit` output):

```
{"trace_id":"a1b2c3d4e5f60708","agent_id":"support-agent","task_name":"classify_customer_ticket","start_time":"2026-04-04T10:00:00Z","status":"success"}
{"trace_id":"a1b2c3d4e5f60708","span_id":"s1","parent_span_id":null,"span_type":"agent_run_started",...}
{"trace_id":"a1b2c3d4e5f60708","span_id":"s2","parent_span_id":"s1","span_type":"model_call",...}
```

- Line 1 is always the trace record
- Lines 2+ are span records
- Blank lines are ignored
- At least one span is required

For full field specifications, see [telemetry.md](../api/telemetry.md).

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
| Empty payload | `"payload is empty"` |
| No spans in payload | `"payload must contain at least one span"` |
| Malformed JSON on any line | `"invalid JSON: ..."` |
| Model validation failure | `"Validation failed: ..."` (wrapped `ActiveRecord::RecordInvalid`) |

```ruby
begin
  result = TelemetryIngester.call(ndjson)
rescue TelemetryIngester::Error => e
  # e.message contains the specific failure reason
end
```

The `Api::V1::TelemetryController` rescues `TelemetryIngester::Error` and returns a `422 Unprocessable Entity` response.

---

## Transaction Semantics

All database writes (one `Trace` + N `Span` records) are wrapped in a single `ActiveRecord::Base.transaction`. If any record fails to save — including the trace or any individual span — all writes are rolled back.

This means a partial payload is never stored. Either the full trace is ingested or nothing is.

---

## Usage in Controllers

```ruby
# app/controllers/api/v1/telemetry_controller.rb
result = TelemetryIngester.call(request.raw_post)
render json: result, status: :created
```

---

## Usage in Tests

```ruby
ndjson = AgentSimulator.new(seed: 42).emit
result = TelemetryIngester.call(ndjson)

expect(result[:spans_ingested]).to eq(7)
expect(Trace.find_by(trace_id: result[:trace_id])).to be_present
```
