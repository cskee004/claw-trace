# Analysis Engine

Three service classes in `app/lib/` provide read-only analysis over stored traces and spans. All follow the same `.call` class-method interface and return plain value objects or hashes — no side effects.

---

## TraceDurationCalculator

`app/lib/trace_duration_calculator.rb`

Calculates elapsed execution time for one or many traces, in milliseconds.

### Single trace

```ruby
duration_ms = TraceDurationCalculator.call(trace)
# => 2340.5   (Float, milliseconds)
# => nil      (if the trace has no spans)
```

**Input:** A single `Trace` record with spans eager-loaded.
**Output:** `Float` (milliseconds from first to last span timestamp), or `nil` if no spans exist.

> Delegates to `Trace#duration` (returns seconds), then multiplies by 1000.0. Does not issue additional queries if spans are already loaded.

### Collection

```ruby
durations = TraceDurationCalculator.call_many(traces)
# => { "a1b2c3d4e5f60708" => 2340.5, "b2c3d4e5f6070809" => 1120.0 }
```

**Input:** An array or `ActiveRecord::Relation` of `Trace` records.
**Output:** `{ trace_id (String) => Float (ms) }` — traces with no spans are absent from the hash.

> Issues a single grouped SQL query (`MIN(timestamp)`, `MAX(timestamp)` grouped by `trace_id`) regardless of collection size. More efficient than calling `.call` in a loop.

---

## ToolCallAnalyzer

`app/lib/tool_call_analyzer.rb`

Aggregates tool invocation statistics from a set of spans.

```ruby
stats = ToolCallAnalyzer.call(spans)
# => {
#      "search"    => { calls: 12, successes: 10, success_rate: 0.833 },
#      "lookup"    => { calls: 5,  successes: 5,  success_rate: 1.0   },
#      "fetch"     => { calls: 3,  successes: 1,  success_rate: 0.333 }
#    }
# => {}   (if no tool_result spans in the input)
```

**Input:** An array or `ActiveRecord::Relation` of `Span` records.
**Output:** `{ "tool_name" => { calls: Integer, successes: Integer, success_rate: Float (0.0–1.0) } }`

**How it works:** Filters the input to `tool_result` spans only, then groups by `metadata["tool_name"]`. A span is counted as a success if `metadata["success"] == true`.

> Only `tool_result` spans carry both `tool_name` and `success` — all other span types are ignored by this analyzer.

---

## ErrorRateAnalyzer

`app/lib/error_rate_analyzer.rb`

Detects which traces contain error spans and computes an overall error rate.

```ruby
result = ErrorRateAnalyzer.call(traces)
# => #<data ErrorRateAnalyzer::Result
#      error_rate=15.0,
#      affected_trace_ids=["a1b2...", "c3d4..."]>

result.error_rate          # => 15.0   (Float, 0.0–100.0)
result.affected_trace_ids  # => ["a1b2c3d4e5f60708", ...]
```

**Input:** An array or `ActiveRecord::Relation` of `Trace` records with spans eager-loaded.
**Output:** `ErrorRateAnalyzer::Result` value object (immutable `Data.define`):
  - `error_rate` — Float percentage of traces that contain at least one `error` span
  - `affected_trace_ids` — Array of `trace_id` strings for those traces

Returns `Result.new(error_rate: 0.0, affected_trace_ids: [])` on empty input.

> A trace is "errored" if any of its spans has `span_type == "error"`. The error span's metadata contents are not inspected.

---

## N+1 Warning

`TraceDurationCalculator.call` and `ErrorRateAnalyzer.call` both access `trace.spans` on each trace. Always eager-load spans before passing traces to these services:

```ruby
# Correct
traces = Trace.includes(:spans).all
ErrorRateAnalyzer.call(traces)
TraceDurationCalculator.call(traces.first)

# Will cause N+1 queries
traces = Trace.all
ErrorRateAnalyzer.call(traces)   # fires one query per trace
```

`TraceDurationCalculator.call_many` handles its own query and does not require pre-loaded spans.

---

## Usage Together

```ruby
traces = Trace.includes(:spans).recent

durations       = TraceDurationCalculator.call_many(traces)
error_result    = ErrorRateAnalyzer.call(traces)
tool_stats      = ToolCallAnalyzer.call(Span.where(trace_id: traces.map(&:trace_id)))

puts "Error rate: #{error_result.error_rate}%"
puts "Avg duration: #{durations.values.sum / durations.size}ms"
puts tool_stats.map { |name, s| "#{name}: #{(s[:success_rate] * 100).round}% success" }
```
