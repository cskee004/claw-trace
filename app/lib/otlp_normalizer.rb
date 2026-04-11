# Translates an OTLP JSON payload (ResourceSpans format) into structured hashes
# accepted by TelemetryIngester.
#
# OTLP input (single resource / single trace):
#   {
#     "resourceSpans": [{
#       "resource": { "attributes": [{key, value}] },
#       "scopeSpans": [{ "spans": [{traceId, spanId, parentSpanId, name,
#                                   startTimeUnixNano, status, attributes}] }]
#     }]
#   }
#
# Output:
#   {
#     trace: { "trace_id", "agent_id", "task_name", "start_time", "status" },
#     spans: [{ "trace_id", "span_id", "parent_span_id", "span_type", "span_name", "timestamp", "agent_id", "metadata" }, ...]
#   }
#
# Span type mapping:
#   openclaw.request      → agent_run_started
#   openclaw.agent.turn   → model_call
#   tool.*                → tool_call
#   openclaw.command.*    → decision
#   ERROR status (code 2) → error  (overrides name-based mapping)
#   final span in trace   → run_completed (unless error)
#
# Timestamps arrive as nanosecond strings and are converted to ISO8601.
# OTLP traceIds (32 hex chars) are truncated to 16 chars to match the DB schema.
# agent_id is read from the openclaw.session.key resource attribute.
#
# Usage:
#   result = OtlpNormalizer.call(otlp_json_string)
#   TelemetryIngester.call(**result)
#
# Raises OtlpNormalizer::Error on malformed input.
class OtlpNormalizer
  Error = Class.new(StandardError)

  SPAN_NAME_MAP = {
    "openclaw.request"    => "agent_run_started",
    "openclaw.agent.turn" => "model_call"
  }.freeze

  OTLP_ERROR_CODE = 2

  def self.call(json_string)
    new(json_string).call
  end

  def initialize(json_string)
    @payload = JSON.parse(json_string.to_s)
  rescue JSON::ParserError => e
    raise Error, "invalid JSON: #{e.message}"
  end

  def call
    resource_spans = Array(@payload["resourceSpans"])
    raise Error, "payload contains no resourceSpans" if resource_spans.empty?

    rs           = resource_spans.first
    resource_attrs = attrs_to_hash(rs.dig("resource", "attributes") || [])
    agent_id     = resource_attrs["openclaw.session.key"] ||
                   resource_attrs["service.name"] ||
                   "unknown"

    all_spans = (rs["scopeSpans"] || []).flat_map { |ss| ss["spans"] || [] }
    raise Error, "resourceSpans contains no spans" if all_spans.empty?

    trace_id    = normalize_trace_id(all_spans.first["traceId"])
    final_span  = find_final_span(all_spans)

    trace_line = build_trace_record(all_spans, trace_id, agent_id, final_span)
    span_lines = all_spans.map { |span| build_span_record(span, trace_id, agent_id, final_span) }

    { trace: trace_line, spans: span_lines }
  end

  private

  # Flattens OTLP's [{key, value: {stringValue|intValue|doubleValue|boolValue}}]
  # into a plain {"key" => scalar} hash. Uses key? to correctly handle boolValue: false.
  # Non-scalar types (arrayValue, kvlistValue, bytesValue) are deliberately omitted —
  # OpenClaw attributes were validated as scalar-only on 2026-04-10.
  def attrs_to_hash(attrs)
    attrs.each_with_object({}) do |attr, hash|
      key   = attr["key"]
      value = attr["value"] || {}
      type  = %w[stringValue intValue doubleValue boolValue].find { |t| value.key?(t) }
      hash[key] = value[type] if type
    end
  end

  def normalize_trace_id(otlp_trace_id)
    otlp_trace_id.to_s[0, 16]
  end

  def nano_to_iso8601(nano)
    Time.at(nano.to_i / 1_000_000_000.0).utc.iso8601(3)
  end

  def nano_to_iso8601_or_nil(nano)
    return nil if nano.nil? || nano.to_i.zero?
    nano_to_iso8601(nano)
  end

  def find_final_span(spans)
    spans.max_by { |s| s["startTimeUnixNano"].to_i }
  end

  def build_trace_record(spans, trace_id, agent_id, final_span)
    earliest_nano = spans.map { |s| s["startTimeUnixNano"].to_i }.min
    root_span     = spans.find { |s| s["parentSpanId"].blank? } || spans.first

    {
      "trace_id"   => trace_id,
      "agent_id"   => agent_id,
      "task_name"  => root_span["name"],
      "start_time" => nano_to_iso8601(earliest_nano),
      "status"     => derive_trace_status(spans, final_span)
    }
  end

  def derive_trace_status(spans, _final_span)
    return "error" if spans.any? { |s| error_status?(s) }

    "success"
  end

  def build_span_record(span, trace_id, agent_id, final_span)
    {
      "trace_id"       => trace_id,
      "span_id"        => span["spanId"],
      "parent_span_id" => span["parentSpanId"].presence,
      "span_type"      => resolve_span_type(span, final_span),
      "span_name"      => span["name"],
      "timestamp"      => nano_to_iso8601(span["startTimeUnixNano"]),
      "end_time"       => nano_to_iso8601_or_nil(span["endTimeUnixNano"]),
      "agent_id"       => agent_id,
      "metadata"       => attrs_to_hash(span["attributes"] || [])
    }
  end

  def resolve_span_type(span, final_span)
    return "error"         if error_status?(span)
    return "run_completed" if span.equal?(final_span)

    map_span_name(span["name"])
  end

  def error_status?(span)
    span.dig("status", "code") == OTLP_ERROR_CODE
  end

  def map_span_name(name)
    return SPAN_NAME_MAP[name] if SPAN_NAME_MAP.key?(name)
    return "tool_call"         if name.to_s.start_with?("tool.")
    return "decision"          if name.to_s.start_with?("openclaw.command.")

    "model_call"
  end
end
