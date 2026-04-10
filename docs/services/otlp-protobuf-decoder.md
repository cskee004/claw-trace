# OtlpProtobufDecoder

`app/lib/otlp_protobuf_decoder.rb`

Pure-Ruby proto3 binary decoder for OTLP trace, metrics, and log payloads. No gems, no native extensions. Implements only the wire-format fields needed for ClawTrace.

---

## Interface

```ruby
hash = OtlpProtobufDecoder.decode_traces(binary_string)
# => {
#   "resourceSpans" => [{
#     "resource" => { "attributes" => [{ "key" => "...", "value" => { "stringValue" => "..." } }] },
#     "scopeSpans" => [{
#       "spans" => [{
#         "traceId" => "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6",  # lowercase hex, 32 chars
#         "spanId" => "aaaa0000aaaa0000",                      # lowercase hex, 16 chars
#         "name" => "openclaw.request",
#         "startTimeUnixNano" => "1712345678000000000",        # decimal nanosecond string
#         "status" => { "code" => 2 },
#         "attributes" => [{ "key" => "model", "value" => { "stringValue" => "claude-3" } }]
#       }]
#     }]
#   }]
# }

hash = OtlpProtobufDecoder.decode_metrics(binary_string)
# => {
#   "resourceMetrics" => [{
#     "scopeMetrics" => [{
#       "metrics" => [{
#         "name" => "gen_ai.client.token.usage",
#         "sum" => { "dataPoints" => [{ "asInt" => 1200, "timeUnixNano" => "1712345678500000000" }] }
#       }]
#     }]
#   }]
# }

hash = OtlpProtobufDecoder.decode_logs(binary_string)
# => {
#   "resourceLogs" => [{
#     "resource" => { "attributes" => [{ "key" => "...", "value" => { "stringValue" => "..." } }] },
#     "scopeLogs" => [{
#       "logRecords" => [{
#         "timeUnixNano"   => "1712345678500000000",             # decimal nanosecond string
#         "severityNumber" => 9,                                 # integer
#         "severityText"   => "INFO",
#         "body"           => { "stringValue" => "agent turn completed" },
#         "traceId"        => "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6",  # lowercase hex; omitted if absent
#         "spanId"         => "ab12cd34ef56a1b2",                    # lowercase hex; omitted if absent
#         "attributes"     => [{ "key" => "service.name", "value" => { "stringValue" => "openclaw" } }]
#       }]
#     }]
#   }]
# }
```

**Input:** Raw binary string (`application/x-protobuf` request body).

**Output:** Ruby Hash with string keys — structurally identical to what `OtlpNormalizer`, `MetricsNormalizer`, and `LogsNormalizer` accept as JSON.

**Raises `OtlpProtobufDecoder::Error`** on truncated or malformed binary. Unknown fields are skipped silently.

---

## Field Decoding

### IDs

`trace_id`, `span_id`, `parent_span_id` arrive as raw bytes and are decoded to lowercase hex strings:

```
16 bytes → "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"  (32 hex chars)
 8 bytes → "aaaa0000aaaa0000"                     (16 hex chars)
```

`OtlpNormalizer` then truncates `traceId` to the first 16 characters.

### Timestamps

`start_time_unix_nano`, `end_time_unix_nano`, `time_unix_nano` are `fixed64` fields decoded as unsigned 64-bit integers and emitted as decimal strings:

```
fixed64 value 1712345678000000000 → "1712345678000000000"
```

The normalizer converts these to ISO 8601 via `Time.at(nano.to_i / 1_000_000_000.0).utc.iso8601(3)`.

### AnyValue

OTLP typed attribute values map to output keys:

| Proto3 field | Output key | Notes |
|---|---|---|
| `string_value` (1) | `stringValue` | UTF-8 encoded |
| `bool_value` (2) | `boolValue` | varint 0/1 → false/true |
| `int_value` (3) | `intValue` | varint |
| `double_value` (4) | `doubleValue` | IEEE 754 double |

> **Proto3 note:** A `boolValue: false` field may be omitted from the wire by strict proto3 encoders (false is the default value). In that case, the attribute will not appear in the decoded output.

### Histogram fields

`bucket_counts` (field 8) and `explicit_bounds` (field 10) are packed repeated fields (wire type 2 containing concatenated values). `count` (field 6) is a varint (`uint64`). `sum`, `min`, `max` are IEEE 754 doubles (`fixed64`).

---

## Integration Pattern

Controllers convert the decoded Hash to JSON before passing to normalizers (which accept JSON strings):

```ruby
# OtlpController
data = OtlpProtobufDecoder.decode_traces(request.raw_post)
result = OtlpNormalizer.call(data.to_json)

# MetricsController
body = OtlpProtobufDecoder.decode_metrics(request.raw_post).to_json
rows = MetricsNormalizer.call(body)

# LogsController
body = OtlpProtobufDecoder.decode_logs(request.raw_post).to_json
rows = LogsNormalizer.call(body)
```

---

## Error Handling

```ruby
OtlpProtobufDecoder.decode_traces("\x8A")
# raises OtlpProtobufDecoder::Error, "truncated protobuf message"
```

Controllers rescue this and return HTTP 400. Error messages are encoded to UTF-8 before JSON serialization (`safe_message` in `MetricsController` and `LogsController`) to prevent `JSON::GeneratorError` on binary input.

---

## Internal Architecture

The `Cursor` struct (`OtlpProtobufDecoder::Cursor`) holds a binary string and a mutable position. Every `parse_*` method receives a Cursor and reads fields sequentially. Nested messages are extracted as sub-cursors via `cur.sub_cursor` (reads the length-delimited byte slice and returns a new Cursor at position 0). Unknown fields are skipped via `cur.skip_field(wire_type)`.
