# MetricsNormalizer

`app/lib/metrics_normalizer.rb`

Translates an OTLP `ExportMetricsServiceRequest` JSON payload into an array of attribute hashes ready for `Metric.insert_all!`. One hash is produced per data point.

---

## Interface

```ruby
rows = MetricsNormalizer.call(json_string)
# => [
#   { "metric_name" => "gen_ai.client.token.usage", "metric_type" => "sum",
#     "trace_id" => "a1b2c3d4e5f6a7b8", "metric_attributes" => { "gen_ai.system" => "anthropic" },
#     "data_points" => { "value" => 1200, "start_time" => "2024-04-05T22:54:38.000Z" },
#     "timestamp" => "2024-04-05T22:54:38.500Z" },
#   ...
# ]
```

**Input:** Raw JSON string (OTLP `ExportMetricsServiceRequest` format).

**Output:** Array of hashes — one per data point, with string keys matching the `metrics` table columns.

**Returns `[]`** for empty or missing `resourceMetrics` — never raises on absent data.

**Raises `MetricsNormalizer::Error`** on malformed JSON.

---

## Supported Metric Types

### Sum

`data_points` hash:

```ruby
{ "value" => 1200, "start_time" => "2024-04-05T22:54:38.000Z" }
```

- `value` — from `asInt` or `asDouble` (whichever is present)
- `start_time` — from `startTimeUnixNano` (omitted if absent)

### Histogram

`data_points` hash:

```ruby
{
  "count"           => 150,
  "sum"             => 45230.0,
  "min"             => 12.0,    # omitted if absent
  "max"             => 890.0,   # omitted if absent
  "bucket_counts"   => [10, 40, 60, 30, 10],
  "explicit_bounds" => [100.0, 300.0, 500.0, 700.0]
}
```

Optional fields (`min`, `max`) are omitted via `.compact` when not present in the payload.

---

## trace_id

`trace_id` is read from the resource attributes (key `"trace_id"`). It is nullable — metrics are accepted and stored without it.

---

## Attribute Flattening

OTLP typed attributes (`[{ key:, value: { stringValue: } }]`) are flattened to a plain hash:

```ruby
[{ "key" => "gen_ai.system", "value" => { "stringValue" => "anthropic" } }]
# => { "gen_ai.system" => "anthropic" }
```

Supported value types: `stringValue`, `intValue`, `doubleValue`, `boolValue`.

---

## Error Handling

```ruby
MetricsNormalizer.call("not json")
# raises MetricsNormalizer::Error, "invalid JSON: ..."
```

All other missing or malformed fields are tolerated — the normalizer never raises on absent optional data.
