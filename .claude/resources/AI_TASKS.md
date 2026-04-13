# AI Development Tasks

## Completed

- ✅ Phase 1 — Simulator (`TelemetryEvent`, `TraceGenerator`, `SpanGenerator`, `AgentSimulator`)
- ✅ Phase 2 — Data Model (`traces` and `spans` tables, ActiveRecord models)
- ✅ Phase 3 — Ingestion API (Bearer token auth, `TelemetryIngester`, `ApiKey`, endpoints)
- ✅ Phase 4 — Observability UI (trace list and timeline views, `TracesController`, seed action)
- ✅ Phase 5 — Analysis Engine (`TraceDurationCalculator`, `ToolCallAnalyzer`, `ErrorRateAnalyzer`)
- ✅ Phase 6 — OTLP Ingestion (`OtlpNormalizer`, controller, route, end-to-end validation)
- ✅ Phase 7 — Metrics Ingestion (`MetricsNormalizer`, `Metric` model, `/v1/metrics` endpoint, UI)
- ✅ Task 19 — Protobuf Support (`OtlpProtobufDecoder`, `application/x-protobuf` routing in both OTLP controllers)
- ✅ Task 33 — Store end_time per Span (`end_time` column, OtlpNormalizer extraction, TelemetryIngester persistence, TracesController latency fix)
- ✅ Task 34 — Non-Scalar Attribute Validation (nil-key fix in attrs_to_hash, comment in parse_any_value)
- ✅ Task 53 — Atomic Multi-Trace Ingestion (outer `ActiveRecord::Base.transaction` in `OtlpController#create`)
- ✅ Task 54 — UTF-8 Encode Error Messages in OtlpController (`safe_message` private method, all three rescue blocks)
- ✅ Task 24 — Add Tailwind CSS (`tailwindcss-rails` gem, Tokyo Night CSS variables, Google Fonts)
- ✅ Task 25 — Restyle Trace List (`traces/index.html.erb` with Tailwind + Turbo Frame, dark theme)

---

# Phase 4 — Observability UI

---

### ✅ Task 12 — Trace List Page

**Changes:**
- `app/views/traces/index.html.erb`
- `TracesController#index`

---

### ✅ Task 13 — Trace Timeline View

**Changes:**
- `app/views/traces/show.html.erb`
- `TracesController#show`

---

# Phase 5 — Analysis Engine

> **Note:** Tasks 14–16 were implemented with slightly different names than originally specified. `TraceDurationAnalyzer` → `TraceDurationCalculator`, `ToolUsageAnalyzer` → `ToolCallAnalyzer`.

---

### ✅ Task 14 — Trace Duration Analyzer

**Changes:**
- New `app/lib/trace_duration_calculator.rb`
- Input: a `Trace` record (`.call`) or collection (`.call_many`)
- Output: duration in milliseconds
- Spec: `spec/lib/trace_duration_calculator_spec.rb`

---

### ✅ Task 15 — Tool Usage Analyzer

**Changes:**
- New `app/lib/tool_call_analyzer.rb`
- Input: a collection of spans
- Output: hash of tool names with call counts and success rates
- Spec: `spec/lib/tool_call_analyzer_spec.rb`

---

### ✅ Task 16 — Error Rate Analyzer

**Changes:**
- New `app/lib/error_rate_analyzer.rb`
- Input: a collection of traces with their spans
- Output: error rate as a percentage, list of affected trace IDs
- Spec: `spec/lib/error_rate_analyzer_spec.rb`

---

# Phase 6 — OTLP Ingestion

---

### ✅ Task 17 — OTLP Controller and Route

**Changes:**
- New `app/controllers/api/v1/otlp_controller.rb`
- Route: `POST /v1/traces`
- Spec: `spec/requests/otlp_spec.rb`

---

### ✅ Task 18 — End-to-End OTLP Validation

**Verification:**
- Full pipeline validated with simulated OpenClaw payload
- Traces and spans render correctly in list and timeline views

---

### ✅ Task 19 — Protobuf Support for OTLP Endpoints

**Context:** OpenClaw sends `application/x-protobuf` exclusively. Both `/v1/traces` and `/v1/metrics` currently 500 on protobuf payloads. This task adds a pure-Ruby protobuf decoder — no gems, no native extensions — and wires it into both controllers. `OtlpNormalizer` and `MetricsNormalizer` must not be modified.

**Changes:**
- New `app/lib/otlp_protobuf_decoder.rb`
  - Two public class methods: `decode_traces(binary)` and `decode_metrics(binary)`
  - Output structurally identical to what normalizers accept as JSON — same camelCase keys, same nesting, same value types
  - Implement primitive decoders: varint, fixed32, fixed64, length-delimited
  - Skip unknown fields silently — never raise on missing optional fields
  - Raise `OtlpProtobufDecoder::Error` on malformed binary (truncated message, bad varint)
  - `trace_id`, `span_id`, `parent_span_id` are raw bytes — decode to lowercase hex strings
  - `start_time_unix_nano` / `end_time_unix_nano` / `time_unix_nano` are fixed64 — output as nanosecond epoch strings
  - `double_value` and float fields (`sum`, `min`, `max`, `asDouble`, `explicitBounds`) are fixed64 IEEE 754 — use `String#unpack1("E")`
  - `bucketCounts` and `explicitBounds` are packed repeated fields — decode as arrays
  - AnyValue output keys: `stringValue`, `boolValue`, `intValue`, `doubleValue`
  - Attributes output format: `[{ "key" => "...", "value" => { "stringValue" => "..." } }]`
  - Proto3 field numbers — traces: `ExportTraceServiceRequest` (1: `resource_spans`), `ResourceSpans` (1: `resource`, 2: `scope_spans`, 3: `schema_url`), `ScopeSpans` (1: `scope`, 2: `spans`, 3: `schema_url`), `Span` (`trace_id`=1, `span_id`=2, `trace_state`=3, `parent_span_id`=4, `name`=5, `kind`=6, `start_time_unix_nano`=7 fixed64, `end_time_unix_nano`=8 fixed64, `attributes`=9, `events`=11 skip, `links`=13 skip, `status`=15, `flags`=16 fixed32), `Status` (`message`=2, `code`=3 varint — 2 means ERROR), `Resource` (`attributes`=1), `KeyValue` (`key`=1, `value`=2), `AnyValue` (`string_value`=1, `bool_value`=2, `int_value`=3, `double_value`=4 fixed64, skip 5–7)
  - Proto3 field numbers — metrics: `ExportMetricsServiceRequest` (1: `resource_metrics`), `ResourceMetrics` (1: `resource`, 2: `scope_metrics`, 3: `schema_url`), `ScopeMetrics` (1: `scope`, 3: `metrics`), `Metric` (1: `name`, 7: `sum`, 9: `histogram`), `Sum` (2: `data_points`), `NumberDataPoint` (2: `start_time_unix_nano` fixed64, 3: `time_unix_nano` fixed64, 4: `as_double` fixed64, 6: `as_int`, 7: `attributes`), `Histogram` (2: `data_points`), `HistogramDataPoint` (2: `start_time_unix_nano` fixed64, 3: `time_unix_nano` fixed64, 6: `count` fixed64, 7: `sum` fixed64, 8: `bucket_counts` packed, 9: `attributes`, 10: `explicit_bounds` packed doubles, 11: `min` fixed64, 12: `max` fixed64)
  - Spec: `spec/lib/otlp_protobuf_decoder_spec.rb` — build binary fixtures by hand-encoding protobuf wire format; traces: decodes ResourceSpans/ScopeSpans/Span structure, all ID fields hex-encoded, timestamps as nanosecond strings, all four AnyValue types, status code 2, empty payload returns `{ "resourceSpans" => [] }`, raises on truncated input; metrics: decodes sum with `asInt` and `asDouble`, histogram with `bucketCounts` and `explicitBounds`, empty payload returns `{ "resourceMetrics" => [] }`
- Modified `app/controllers/api/v1/otlp_controller.rb` — check `Content-Type` before parsing; `application/x-protobuf` → `OtlpProtobufDecoder.decode_traces` → pass to `OtlpNormalizer`; rescue `OtlpProtobufDecoder::Error` → 400; add valid/malformed protobuf cases to `spec/requests/otlp_spec.rb`
- Modified `app/controllers/api/v1/metrics_controller.rb` — same content-type branching using `decode_metrics`; fix pre-existing bug: force-encode error message to UTF-8 before rendering JSON to prevent `JSON::GeneratorError`; add valid/malformed protobuf cases to `spec/requests/metrics_spec.rb`
- New `docs/services/otlp-protobuf-decoder.md`
- Updated `docs/api/otlp.md` and `docs/api/metrics.md` — note `application/x-protobuf` accepted alongside `application/json`

**Verification:**
- `bundle exec rspec` — full suite green
- `bundle exec rubocop app/lib/otlp_protobuf_decoder.rb` — no offenses
- `bundle exec brakeman` — no new warnings
- POST real OpenClaw protobuf payload to `/v1/traces` via ngrok — trace appears in `/traces`
- POST real OpenClaw protobuf payload to `/v1/metrics` via ngrok — metric appears in `/metrics`
- `OtlpNormalizer` and `MetricsNormalizer` are unmodified
- No new gems added to Gemfile

---

# Phase 7 — Metrics Ingestion

---

### ✅ Task 20 — Metrics Data Model

**Changes:**
- Migration for `metrics` table with: `trace_id` (nullable, indexed), `metric_name` (string, indexed), `metric_type` (string — `"sum"` or `"histogram"`), `metric_attributes` (JSON — renamed from `attributes`, reserved by ActiveRecord), `data_points` (JSON — sum: `{ "value": 42, "start_time": "..." }`, histogram: `{ "count": 150, "sum": 45230, "min": 12, "max": 890, "bucket_counts": [...], "explicit_bounds": [...] }`), `timestamp` (datetime, indexed), `created_at`
- `Metric` ActiveRecord model
- Spec: `spec/models/metric_spec.rb`

---

### ✅ Task 21 — MetricsNormalizer

**Changes:**
- New `app/lib/metrics_normalizer.rb`
- Input: OTLP `ExportMetricsServiceRequest` JSON payload
- Output: array of attribute hashes ready for `Metric.create!`
- Handle `sum` and `histogram` data point types
- Reuse same attribute flattening pattern as `OtlpNormalizer#attrs_to_hash`
- `trace_id` is nullable — never fail if absent
- Spec: `spec/lib/metrics_normalizer_spec.rb`

---

### ✅ Task 22 — `/v1/metrics` Controller and Route

**Changes:**
- New `app/controllers/api/v1/metrics_controller.rb` — `POST /v1/metrics`, unauthenticated, parse body → `MetricsNormalizer` → `Metric.create!`, return `{}` HTTP 200, return 400 on malformed JSON
- Route added to `config/routes.rb`
- Spec: `spec/requests/metrics_spec.rb` — valid payload returns 200 with `{}`, empty `resourceMetrics` returns 200, malformed JSON returns 400

---

### Task 42 — Gauge Metric Support in MetricsNormalizer

**Context:** `MetricsNormalizer#normalize_metric` only handles `sum` and `histogram` OTLP metric types. The `else` branch silently returns `[]`, meaning gauge data points are dropped without error. Scenarios 02, 03, and 04 of the OpenClaw OTLP fixture suite all emit gauge metrics (`cache.hit_ratio`, `deploy.replicas.ready`, `service.up`). Without this fix those rows will never be stored.

**Changes:**
- Add a `gauge` branch in `normalize_metric` alongside `sum` and `histogram`
- Add a `"gauge"` case in `extract_data_points` — gauge data points carry a single scalar value (`asDouble` or `asInt`), identical in shape to `sum` data points; reuse that logic
- Update `spec/lib/metrics_normalizer_spec.rb` with a gauge data point test case (scalar value stored, `metric_type` = `"gauge"`)

**Verification:**
- `bundle exec rspec spec/lib/metrics_normalizer_spec.rb` — green
- `bundle exec rubocop app/lib/metrics_normalizer.rb` — no offenses
- Gauge rows appear in the `metrics` table after ingesting a payload that includes a `gauge` metric

---

### ✅ Task 23 — Metrics UI

**Changes:**
- New metrics tab alongside the existing traces tab
- Metrics index view — list of metric names with latest value and timestamp, filterable by `metric_name` and by attributes (channel, model, provider)
- Time series view per metric — counters: value over time; histograms: P50/P95/P99 computed from bucket data
- Built with Hotwire (Turbo + Stimulus), consistent with existing UI patterns

---

# Protobuf Decoder — Known Gaps

Identified during architecture review on 2026-04-10.

---

### ✅ Task 33 — Store `endTimeUnixNano` per Span

**Context:** `OtlpProtobufDecoder` correctly decodes `endTimeUnixNano` (field 8) for each span, but `OtlpNormalizer` discards it. `TracesController` currently estimates span duration by comparing consecutive span start times, which is an approximation. Storing the actual end time would give accurate per-span duration without guesswork.

**Changes:**
- Add `end_time` (datetime, nullable) column to the `spans` table via a new migration
- Update `OtlpNormalizer#build_span_record` to include `"end_time"` from `endTimeUnixNano` when present
- Update `TelemetryIngester#persist_span` to write `end_time`
- Update `TracesController#compute_latencies_ms` (or replace) to use `end_time - timestamp` when available, falling back to consecutive-start-time approximation when `end_time` is nil
- Update `Span` model with the new column
- Update `spec/lib/otlp_normalizer_spec.rb` and `spec/lib/telemetry_ingester_spec.rb`

**Verification:**
- `bundle exec rspec` — full suite green
- Span duration in the timeline view reflects actual measured end times for OTLP-ingested spans

---

### ✅ Task 34 — Validate Non-Scalar Attribute Values from OpenClaw

**Context:** `OtlpNormalizer#attrs_to_hash` and `OtlpProtobufDecoder#parse_any_value` only handle `stringValue`, `boolValue`, `intValue`, and `doubleValue`. OTLP also supports `arrayValue`, `kvlistValue`, and `bytesValue`. If OpenClaw sends any attribute with these types, the key is silently dropped from `metadata` with no error or warning. Research confirmed (2026-04-10): OpenClaw's documented attributes are all scalars. This task validates that assumption holds and adds a safety net in case it changes.

**Changes:**
- Audit the actual OTLP payloads OpenClaw sends (via ngrok or log capture) and confirm no non-scalar attribute values are present
- If non-scalar values are found: extend `attrs_to_hash` and `parse_any_value` to handle them (e.g. serialize `arrayValue` as a JSON array, `kvlistValue` as a nested hash)
- If all scalar: add a comment to both methods noting the deliberate omission and the date it was validated
- Either way: add a test case to `spec/lib/otlp_normalizer_spec.rb` covering an attribute with an unknown value type to confirm it is skipped gracefully (no crash, no nil key)

**Verification:**
- `bundle exec rspec` — full suite green
- No silent data loss on known OpenClaw payloads

---

### ✅ Task 35 — `logs` Table and Model

**Changes:**
- Migration for `logs` table with: `trace_id` (string, nullable, indexed), `span_id` (string, nullable, indexed), `severity_text` (string, nullable), `severity_number` (integer, nullable), `body` (text, nullable), `log_attributes` (JSON), `timestamp` (datetime, indexed), `created_at`
- `Log` ActiveRecord model with `belongs_to :trace, foreign_key: :trace_id, primary_key: :trace_id, optional: true`
- Spec: `spec/models/log_spec.rb`

**Verification:**
- `bundle exec rspec spec/models/log_spec.rb` — green
- Migration is reversible

---

### ✅ Task 36 — LogsNormalizer

**Prerequisite:** Task 35

**Changes:**
- New `app/lib/logs_normalizer.rb`
- Input: parsed `ExportLogsServiceRequest` JSON payload
- Output: array of attribute hashes ready for `Log.insert_all!`
- Copy `attrs_to_hash` pattern locally — do not share with other normalizers
- Extract `traceId`/`spanId` as lowercase hex strings when present
- Extract `severityText`, `severityNumber`, `body.stringValue`
- All fields nullable — never fail on missing optional fields
- Spec: `spec/lib/logs_normalizer_spec.rb` — well-formed payload, missing `traceId`/`spanId`, missing `body`, unknown attribute value types

**Verification:**
- `bundle exec rspec spec/lib/logs_normalizer_spec.rb` — green
- `bundle exec rubocop app/lib/logs_normalizer.rb` — no offenses

---

### ✅ Task 37 — `POST /v1/logs` Controller and Route

**Prerequisite:** Task 36

**Changes:**
- New `app/controllers/api/v1/logs_controller.rb` — accepts `application/json`, parse body → `LogsNormalizer` → `Log.insert_all!`, returns `{}` HTTP 200, rescue `JSON::ParserError` → 400 with UTF-8-encoded error message
- Route: `post "/v1/logs", to: "api/v1/logs#create", format: false`
- Spec: `spec/requests/logs_spec.rb` — valid payload returns 200 with `{}`, empty `resourceLogs` returns 200, malformed JSON returns 400

**Verification:**
- `bundle exec rspec spec/requests/logs_spec.rb` — green
- `bundle exec rubocop app/controllers/api/v1/logs_controller.rb` — no offenses
- `bundle exec brakeman` — no new warnings

---

### ✅ Task 38 — Protobuf Support for `/v1/logs`

**Prerequisite:** Task 37

**Changes:**
- Add `OtlpProtobufDecoder.decode_logs(binary)` to `app/lib/otlp_protobuf_decoder.rb`
- Proto3 fields: `ExportLogsServiceRequest` (1: `resource_logs`), `ResourceLogs` (1: `resource`, 2: `scope_logs`, 3: `schema_url`), `ScopeLogs` (1: `scope`, 2: `log_records`), `LogRecord` (1: `time_unix_nano` fixed64, 2: `severity_number` varint, 3: `severity_text`, 5: `body` AnyValue, 6: `attributes`, 9: `trace_id` bytes→hex, 10: `span_id` bytes→hex)
- Empty payload returns `{ "resourceLogs" => [] }`
- Raises `OtlpProtobufDecoder::Error` on malformed binary
- Wire into `LogsController`: `application/x-protobuf` → `decode_logs` → existing normalizer path; rescue `OtlpProtobufDecoder::Error` → 400
- Add to `spec/lib/otlp_protobuf_decoder_spec.rb`: full `LogRecord` decode, hex IDs, missing IDs return nil, empty payload
- Add to `spec/requests/logs_spec.rb`: valid protobuf returns 200, malformed protobuf returns 400

**Verification:**
- `bundle exec rspec` — full suite green
- `bundle exec rubocop app/lib/otlp_protobuf_decoder.rb` — no offenses

---

### ✅ Task 40 — Logs Docs and Schema

**Prerequisite:** Task 37

**Changes:**
- New `docs/services/logs-normalizer.md` — follow format of existing service docs
- Updated `docs/api/otlp.md` — document `POST /v1/logs`, content types, response format
- Updated `docs/reference/schema.md` — add `logs` table

---

### ✅ Task 43 — Add `name` Column to `spans` Table

**Changes:**
- Migration adding `name` (string, nullable) column to the `spans` table

**Verification:**
- Migration is reversible
- `bundle exec rspec` — full suite green

---

### ✅ Task 44 — Store Span Name from OTLP Payloads

**Prerequisite:** Task 43

**Changes:**
- Update `OtlpNormalizer#build_span_record` to include `"name"` from `span["name"]`
- Update `TelemetryIngester#persist_span` to write `name`
- Update `Span` model with the new column
- Update `spec/lib/otlp_normalizer_spec.rb` and `spec/lib/telemetry_ingester_spec.rb`

**Verification:**
- `bundle exec rspec` — full suite green
- Span `name` (e.g. `agent.turn.process`, `llm.inference`) appears in the `spans` table after OTLP ingestion

---

### ✅ Task 45 — Display Span Name in Trace Timeline

**Prerequisite:** Task 44

**Changes:**
- Render `span.name` in the span card in `app/views/traces/show.html.erb`, alongside the existing `span_type` badge

**Verification:**
- Ingest an OTLP trace — span names appear in the timeline view

---

### ✅ Task 46 — Indent Timeline Spans by Parent Depth

**Changes:**
- Compute nesting depth for each span from the `parent_span_id` chain before rendering
- Apply left indentation (16px per level) to each span card in `app/views/traces/show.html.erb`

**Verification:**
- Ingest a trace with nested spans — child spans are visually indented under their parents

---

### Task 47 — Add Session Filter to Trace List

**Changes:**
- Add a session ID text input to the filter form in `app/views/traces/index.html.erb`
- Update `TracesController#index` to filter by `agent.session.id` span metadata when the param is present

**Verification:**
- Filtering by a session ID returns only traces whose spans carry that `agent.session.id` attribute

---

### ✅ Task 48 — Rename `spans.name` to `spans.span_name`

**Prerequisite:** Task 43

**Context:** The `name` column added in Task 43 does not follow the `span_*` prefix convention used by all other columns in the `spans` table (`span_id`, `span_type`, etc.). This refactor aligns the column name with the existing convention and updates all references.

**Changes:**
- Migration renaming `spans.name` to `spans.span_name`
- Update `Span` model if the column is referenced explicitly
- Update `OtlpNormalizer`, `TelemetryIngester`, and any view referencing `span.name` to use `span_name`
- Update any affected specs

**Verification:**
- Migration is reversible
- `bundle exec rspec` — full suite green
- `bundle exec rubocop` — no offenses

---

### ✅ Task 49 — Sync AI_ARCHITECTURE.md with Current Implementation

**Prerequisite:** Task 48

**Context:** `AI_ARCHITECTURE.md` has drifted from the actual codebase across several phases. The storage model is missing columns added in later tasks, the analyzer class names don't match what shipped, and the canonical span types list predates the OTLP integration work.

**Changes:**
- Update the Storage Model section to reflect current `spans` columns: `span_name`, `end_time`, `agent_id`
- Update the Analysis Layer section to use the correct class names: `TraceDurationCalculator`, `ToolCallAnalyzer`, `ErrorRateAnalyzer`
- Update the Canonical Span Types list if any types were added or changed during implementation
- Update the Span model field list to include `span_name` and `end_time`
- Add a note on column naming convention: all `spans` columns use `span_*` prefix

**Verification:**
- Every class name, column name, and endpoint in the document matches the actual codebase

---

### ✅ Task 50 — Handle Multiple `resourceSpans` Entries in `OtlpNormalizer`

**Context:** `OtlpNormalizer` only processes the first `resourceSpans` entry in a payload. Scenarios 2 and 4 send 3 and 5 entries respectively — one per service. All spans after the first entry are silently ignored, causing entire services to disappear from the stored trace.

**Prereqs:** None

**Changes:**
- Update `OtlpNormalizer#call` to iterate over all `resourceSpans` entries rather than only the first
- Resolve `service.name` and `agent_id` per entry from each entry's `resource.attributes`
- Aggregate spans from all entries into a single span set under the shared `traceId`
- Update `spec/lib/otlp_normalizer_spec.rb` with a multi-service payload test case

**Verification:**
- `bundle exec rspec spec/lib/otlp_normalizer_spec.rb` — green
- Scenario 2: payment-service and notification-service spans appear in the timeline
- Scenario 4: all 5 service sub-trees appear in the timeline

---

### ✅ Task 51 — Fix Span Tree Rendering with DFS Pre-Order Traversal

**Context:** The timeline view sorts spans by timestamp then applies depth-based indentation. This misattributes spans when two spans at the same depth appear consecutively in the list but belong to different parent chains — visible in Scenario 1 where `http.client.request` renders under the wrong parent, and Scenario 5 where the root span appears mid-list.

**Prereqs:** Task 46

**Changes:**
- Replace the sort-by-timestamp ordering in `TracesController#show` with a DFS pre-order tree traversal
- Children always immediately follow their parent in the rendered output, regardless of timestamp
- Update `TracesHelper` and its spec to cover the traversal logic

**Verification:**
- `bundle exec rspec` — full suite green
- Scenario 1: `http.client.request` renders under `tool.exec.web_search`, not `llm.inference`
- Scenario 5: `agent.task` renders as the first row with all children correctly beneath it

---

### ✅ Task 52 — Handle Multiple Distinct `traceId` Values in a Single OTLP Payload

**Context:** `OtlpNormalizer` builds one trace record per call. Scenario 7 sends 3 agent turns in one payload, each with a distinct `traceId`. Only the first trace is persisted — Traces 2 and 3 are dropped entirely.

**Prereqs:** Task 50

**Changes:**
- Update `OtlpNormalizer#call` to group spans by `traceId` before processing
- Produce a separate trace + span set for each distinct `traceId` found in the payload
- Return an array of results rather than a single result when multiple traces are present
- Update `OtlpController` to handle the array response and call `TelemetryIngester` once per trace
- Update `spec/lib/otlp_normalizer_spec.rb` and `spec/requests/otlp_spec.rb` with multi-trace payload cases

**Verification:**
- `bundle exec rspec` — full suite green
- Scenario 7: all 3 traces appear independently in the trace list with correct span counts

---

### ✅ Task 53 — Prevent Partial Persistence on Multi-Trace OTLP Payload Failure

**Context:** `OtlpController` iterates the array returned by `OtlpNormalizer` and calls `TelemetryIngester` once per trace. Each `TelemetryIngester` call wraps only its own trace in a transaction. If a payload contains three distinct traceIds and the second `TelemetryIngester.call` raises an error, trace A is already committed while trace C is never written. The controller then returns a 400, causing the OTLP sender to retry the full payload — trace A is duplicated on retry.

**Prereqs:** Task 52

**Changes:**
- Wrap the `results.each` iteration in `OtlpController#create` in a single `ActiveRecord::Base.transaction` block so all traces in a multi-trace payload are committed atomically or not at all
- On failure, the entire payload is rolled back and the 400 response is correct for a retry

**Verification:**
- `bundle exec rspec` — full suite green
- A payload with two valid traces and one invalid trace persists zero traces (not one)

---

### ✅ Task 54 — UTF-8 Encode Error Messages in `OtlpController` Rescue Blocks

**Context:** `MetricsController` and `LogsController` both force-encode `e.message` to UTF-8 before rendering JSON, preventing `JSON::GeneratorError` when binary protobuf input produces a non-UTF-8 error string. `OtlpController` renders `e.message` raw — a malformed protobuf payload can cause a 500 instead of a clean 400. This is documented in CLAUDE.md Gotchas.

**Prereqs:** None

**Changes:**
- Add a `safe_message(e)` private method to `OtlpController` that force-encodes `e.message` to UTF-8 with invalid/undefined bytes replaced: `e.message.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")`
- Use `safe_message(e)` in all three rescue blocks instead of `e.message`
- Add a request spec in `spec/requests/otlp_spec.rb` covering a raw binary (non-UTF-8) payload that returns 400 with a parseable JSON body

**Verification:**
- `bundle exec rspec spec/requests/otlp_spec.rb` — green
- `bundle exec rubocop app/controllers/api/v1/otlp_controller.rb` — no offenses
- POST a raw binary payload to `/v1/traces` with `Content-Type: application/x-protobuf` containing non-UTF-8 bytes in the error path — response is 400, not 500

---

# Phase 8 — UI Polish & Frontend Foundations

Upgrade the existing ERB + Hotwire views with Tailwind CSS, Turbo Frames for panel-scoped updates, and a more polished trace/span visualization. Lays the groundwork for Phase 9 dashboard charts.

Frontend conventions for this phase: Tailwind CSS for all new styling — utility-first, no custom CSS files. Turbo Frames for panel isolation (no full-page reloads on list filters). Stimulus controllers kept small and single-purpose. ERB partials for now; migrate to ViewComponent when a partial exceeds ~50 lines or needs isolated testing. Hotwire-progressive: plain HTML/CSS first → Turbo Frames → Stimulus only when needed.

---

### ✅ Task 24 — Add Tailwind CSS

**Changes:**
- Add `tailwindcss-rails` gem (self-contained, no Node required)
- Configure `tailwind.config.js` to scan `app/views/**/*.html.erb` and `app/javascript/**/*.js`
- Add `<%= stylesheet_link_tag "tailwind" %>` to `app/views/layouts/application.html.erb`
- Do not remove existing styles yet — Tailwind layers in alongside current markup
- No visual changes required in this task; just installation and pipeline wiring

**Verification:**
- `rails tailwindcss:build` runs without errors

---

### ✅ Task 25 — Restyle Trace List with Tailwind + Turbo Frame

**Prerequisite:** Task 24

**Changes:**
- Restyle `app/views/traces/index.html.erb` using Tailwind
- Wrap the trace table in `<turbo-frame id="trace_list">`
- Filter form targets the same Turbo Frame — no controller changes required
- Each row shows: agent_id, task_name, status badge (color-coded), start_time, duration
- Status badges: success = green, error = red, in_progress = yellow
- Visual goal: clean table with monospace agent IDs, clear status at a glance

---

### Task 26 — Waterfall Span Timeline View

**Prerequisite:** Task 24

**Changes:**
- Replace the current flat span list in `app/views/traces/show.html.erb` with a CSS waterfall timeline
- Each span is a row: label column (left) + proportional bar column (right); bar left offset and width are percentages of total trace duration; all layout is pure CSS (flexbox + percentage widths) — no JS for bar positioning
- Indentation in the label column encodes parent-child depth (16px per level), computed from `parent_span_id` via `TracesHelper#span_depth_map`
- Minimum bar width of 4px so zero-duration spans are still visible
- Color coding by span_type: `agent_run_started` / `run_completed` → slate/gray, `model_call` / `model_response` → violet/purple, `tool_call` / `tool_result` → blue, `decision` → amber, `error` → red
- Stimulus controller `span_detail`: clicking a span row toggles a metadata drawer; drawer renders `metadata` JSON as a readable key/value list; single `toggle()` action and `open` CSS class
- Add `TracesHelper` spec covering the `span_depth_map` calculation

---

### Task 27 — Inline Trace Row Expansion

**Prerequisite:** Task 25, Task 26

**Context:** Clicking a trace row currently navigates to the full `traces/:id`
timeline page. This task adds inline expansion: clicking a row toggles a detail
drawer beneath it showing the first N spans without leaving the list. Revisit
scope and implementation after Task 26 is complete.

---

### Task 39 — Span Log Drawer UI

**Prerequisite:** Tasks 35 and 26

**Changes:**
- Add a "Logs" section to the span metadata drawer from Task 26
- Load via Turbo Frame when drawer opens — no eager loading on page load
- Query: `Log.where(span_id: span.span_id).order(:timestamp)`
- Render each line as `[severity_text] body` with timestamp
- Severity color-coding: ERROR/FATAL → red, WARN → amber, INFO → default, DEBUG → muted
- Render nothing if no logs are associated

**Verification:**
- Ingest a trace + matching log records via `/v1/traces` and `/v1/logs` — log lines appear in drawer
- Span with no associated logs — drawer shows no logs section

---

### Task 27 — Turbo Frame Panel Isolation on Trace Show Page

**Prerequisite:** Task 26

**Changes:**
- Wrap independent panels on the trace show page in Turbo Frames so they can reload without a full page refresh
- Panels to isolate: trace summary header (status, agent, duration), waterfall timeline, span metadata drawer (if rendered server-side)
- Sets up the page for real-time updates in Task 28 without structural rework

---

### Task 28 — Real-Time Trace Ingestion via Turbo Streams

**Prerequisite:** Tasks 26 and 27

**Changes:**
- Subscribe the trace show page to a `TraceChannel` scoped to the current `trace_id`
- `TelemetryIngester` broadcasts a Turbo Stream `append` after each span is saved
- New span rows append to the waterfall in real time, ordered by timestamp
- No polling — pure WebSocket push via Action Cable

---

# Phase 9 — Dashboard Charts

Add analysis charts to the dashboard using Chartkick (for simple metrics) and ApexCharts.rb (for timeline/range charts). All chart data is served from dedicated controller actions returning JSON — keeping page load fast.

Charting conventions: simple bar/line/pie charts → Chartkick + Chart.js (no new gem beyond `chartkick`). Timeline/range/gantt charts → ApexCharts.rb. Each chart gets its own JSON endpoint — never block page load on chart queries. Charts live inside Turbo Frames. Pass data from Rails to JS via Stimulus `values` (data attributes) — no inline `<script>` tags.

---

### Task 29 — Add Chartkick

**Changes:**
- Add `chartkick` gem to Gemfile
- Add Chart.js via importmap: `bin/importmap pin chartkick` and `bin/importmap pin chart.js`
- Confirm `<%= javascript_importmap_tags %>` is present in layout
- No charts built yet — installation and smoke test only

**Verification:**
- `<%= bar_chart [["Tool A", 5], ["Tool B", 3]] %>` renders in a view

---

### Task 30 — Tool Call Frequency Chart

**Prerequisite:** Task 29

**Changes:**
- New controller action `TracesController#tool_stats` returns JSON sourced from `ToolCallAnalyzer`
- Rendered with Chartkick: `<%= bar_chart tool_stats_trace_path(@trace), ... %>`
- Chart inside a Turbo Frame so it loads asynchronously after the main page
- X axis: tool name, Y axis: call count; secondary series for success rate (%)

---

### Task 31 — Error Rate Over Time Chart

**Prerequisite:** Task 29

**Changes:**
- New controller action `DashboardController#error_rate` returns JSON sourced from `ErrorRateAnalyzer` scoped to a date range
- Rendered with Chartkick: `<%= line_chart error_rate_dashboard_path %>`
- Chart inside a Turbo Frame, loaded asynchronously
- X axis: date, Y axis: error rate (%)

---

### Task 32 — Span Duration Breakdown Chart (ApexCharts)

**Prerequisite:** Tasks 26 and 29

**Changes:**
- Add `apexcharts` gem to Gemfile
- New controller action returns span start/end offsets as JSON
- Rendered via a Stimulus controller that initializes an ApexCharts timeline instance
- Data passed from Rails via `data-chart-series-value` attribute (Stimulus values pattern)
- Color series by `span_type` to match the waterfall color coding defined in Task 26
- Richer, zoomable complement to the CSS waterfall for detailed span analysis

---

### Task 41 — Log Pruning / TTL Strategy

**Context:** Log records can arrive at far higher volume than traces or metrics — a single agent run may emit hundreds of log lines. Without a pruning strategy, the `logs` table will grow unbounded and degrade query performance over time.

**Changes:**
- Design and implement a pruning strategy; options to evaluate: scheduled job (Rufus-Scheduler or Active Job + cron) deleting `Log` records older than a configurable retention window (e.g. 30 days); database-level TTL trigger (SQLite: not supported natively; PostgreSQL: consider `pg_partman` or a periodic job); soft cap: delete oldest N rows when count exceeds a threshold
- Add `rails runner` or rake task as a minimum viable approach — no new background job infrastructure required unless justified
- Add a configuration constant (not hardcoded) for the retention window
- Document the chosen strategy in `docs/reference/schema.md` under the `logs` table section

**Verification:**
- Old log records are deleted when the pruning job/rake task runs
- Recent log records are retained
- Rake task or runner command is documented

---

# Polish

---

### Task 53 — Strengthen Multi-Trace Rollback Assertion in Tests

**Context:** A code review flagged that the multi-trace ingestion test asserts `not_to change(Trace, :count)` on rollback but does not make the same assertion for `Span`. Spans are also rolled back by the outer transaction, but the omission means the test only half-documents the guarantee. Non-blocking, but worth making explicit.

**Prereqs:** Task 52

**Changes:**
- Add `not_to change(Span, :count)` alongside the existing `not_to change(Trace, :count)` assertion in the relevant spec

**Verification:**
- `bundle exec rspec` — full suite green

---

# Phase 10 — ClawTrace OpenClaw Plugin

Publish a first-party `clawtrace-openclaw` plugin so users can install ClawTrace observability with a single command:

```bash
openclaw plugins install clawtrace
```

The plugin should use OpenClaw's hook-based plugin SDK, send telemetry directly to the ClawTrace Bearer token API, and bundle ClawTrace API key configuration into the OpenClaw config flow. This is the primary distribution and adoption strategy for ClawTrace.

---

# Development Workflow

1. Read relevant code before proposing changes
2. Propose implementation steps and wait for approval
3. Generate small, focused changes one task at a time
4. Run the full test suite before declaring a task complete

Tasks should not modify unrelated