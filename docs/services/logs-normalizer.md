# LogsNormalizer

`app/lib/logs_normalizer.rb`

Translates an OTLP `ExportLogsServiceRequest` JSON payload into an array of attribute hashes ready for `Log.insert_all!`. One hash is produced per log record.

---

## Interface

```ruby
rows = LogsNormalizer.call(json_string)
# => [
#   { "trace_id" => "a1b2c3d4e5f6a7b8", "span_id" => "ab12cd34ef56a1b2",
#     "severity_text" => "INFO", "severity_number" => 9,
#     "body" => "agent turn completed",
#     "log_attributes" => { "service.name" => "openclaw" },
#     "timestamp" => "2024-04-05T22:54:38.500Z" },
#   ...
# ]
```

**Input:** Raw JSON string (OTLP `ExportLogsServiceRequest` format).

**Output:** Array of hashes — one per log record, with string keys matching the `logs` table columns.

**Returns `[]`** for empty or missing `resourceLogs` — never raises on absent data.

**Raises `LogsNormalizer::Error`** on malformed JSON.

---

## OTLP Input Format

```json
{
  "resourceLogs": [{
    "resource": { "attributes": [] },
    "scopeLogs": [{
      "logRecords": [{
        "timeUnixNano": "1712345678500000000",
        "severityText": "INFO",
        "severityNumber": 9,
        "body": { "stringValue": "agent turn completed" },
        "traceId": "a1b2c3d4e5f6a7b8",
        "spanId": "ab12cd34ef56a1b2",
        "attributes": [
          { "key": "service.name", "value": { "stringValue": "openclaw" } }
        ]
      }]
    }]
  }]
}
```

---

## Field Mapping

| OTLP field | Output column | Notes |
|---|---|---|
| `timeUnixNano` | `timestamp` | Nanosecond string → ISO 8601 with ms precision; nil when absent |
| `severityText` | `severity_text` | Passed through as-is; nil when absent |
| `severityNumber` | `severity_number` | Integer; nil when absent |
| `body.stringValue` | `body` | Nil when `body` is absent or not a `stringValue` |
| `traceId` | `trace_id` | Lowercased; nil when absent or blank |
| `spanId` | `span_id` | Lowercased; nil when absent or blank |
| `attributes` | `log_attributes` | Flattened OTLP typed attributes (see below); always a hash, `{}` when key is absent |

All fields are nullable — the normalizer never fails on missing data.

---

## Attribute Flattening

OTLP typed attributes (`[{ key:, value: { stringValue: } }]`) are flattened to a plain hash:

```ruby
[{ "key" => "service.name", "value" => { "stringValue" => "openclaw" } }]
# => { "service.name" => "openclaw" }
```

Supported value types: `stringValue`, `intValue`, `doubleValue`, `boolValue`.

Non-scalar types (`arrayValue`, `kvlistValue`, `bytesValue`) are silently omitted — OpenClaw attributes were validated as scalar-only on 2026-04-10.

---

## Timestamp Conversion

```
"1712345678500000000"  →  "2024-04-05T22:54:38.500Z"
```

Converted via `Time.at(nano.to_i / 1_000_000_000.0).utc.iso8601(3)`. Returns nil when `timeUnixNano` is absent.

---

## Error Handling

```ruby
LogsNormalizer.call("not json")
# raises LogsNormalizer::Error, "invalid JSON: ..."
```

All other missing or malformed fields are tolerated — the normalizer never raises on absent optional data.
