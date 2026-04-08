# OTLP Metrics Ingestion API

ClawTrace accepts OpenTelemetry Protocol (OTLP) metrics payloads. OpenClaw users can point their metrics exporter directly at ClawTrace.

---

## Endpoint

```
POST /v1/metrics
Content-Type: application/json
```

No authentication required — OTLP endpoints are unauthenticated by convention.

---

## Request

The body must be a JSON object conforming to the OTLP `ExportMetricsServiceRequest` format:

```json
{
  "resourceMetrics": [
    {
      "resource": {
        "attributes": [
          { "key": "trace_id", "value": { "stringValue": "a1b2c3d4e5f6a7b8" } }
        ]
      },
      "scopeMetrics": [
        {
          "metrics": [
            {
              "name": "gen_ai.client.token.usage",
              "sum": {
                "dataPoints": [
                  {
                    "attributes": [
                      { "key": "gen_ai.system", "value": { "stringValue": "anthropic" } }
                    ],
                    "startTimeUnixNano": "1712345678000000000",
                    "timeUnixNano": "1712345678500000000",
                    "asInt": 1200
                  }
                ]
              }
            }
          ]
        }
      ]
    }
  ]
}
```

---

## Supported Metric Types

### Sum

```json
{
  "name": "gen_ai.client.token.usage",
  "sum": {
    "dataPoints": [
      {
        "attributes": [...],
        "timeUnixNano": "1712345678500000000",
        "startTimeUnixNano": "1712345678000000000",
        "asInt": 1200
      }
    ]
  }
}
```

`asDouble` is also accepted when `asInt` is absent. `startTimeUnixNano` is optional.

### Histogram

```json
{
  "name": "gen_ai.client.operation.duration",
  "histogram": {
    "dataPoints": [
      {
        "attributes": [...],
        "timeUnixNano": "1712345678500000000",
        "count": 150,
        "sum": 45230.0,
        "min": 12.0,
        "max": 890.0,
        "bucketCounts": [10, 40, 60, 30, 10],
        "explicitBounds": [100.0, 300.0, 500.0, 700.0]
      }
    ]
  }
}
```

`min` and `max` are optional.

---

## Responses

**200 OK** — always returned on success (per OTLP spec)

```json
{}
```

**200 OK** — also returned for empty or missing `resourceMetrics` (no-op, nothing persisted)

**400 Bad Request** — malformed JSON body

```json
{ "error": "invalid JSON: ..." }
```

---

## trace_id

`trace_id` is read from the resource attributes (key `trace_id`). It is optional — metrics are accepted without it.

---

## Metric Attributes

Metric data point attributes use OTLP's typed value format:

```json
{ "key": "gen_ai.system", "value": { "stringValue": "anthropic" } }
```

Supported value types: `stringValue`, `intValue`, `doubleValue`, `boolValue`.

Attributes are flattened into ClawTrace's `metric_attributes` JSON column:

```json
{ "gen_ai.system": "anthropic", "gen_ai.response.model": "claude-sonnet-4-6" }
```

---

## Timestamp Conversion

OTLP timestamps are nanosecond Unix epoch strings and are converted to ISO 8601 millisecond precision:

```
"1712345678500000000"  →  "2024-04-05T22:54:38.500Z"
```
