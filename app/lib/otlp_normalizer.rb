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
# Output: Array of result hashes, one per distinct traceId.
#   [
#     {
#       trace: { "trace_id", "agent_id", "task_name", "start_time", "status" },
#       spans: [{ "trace_id", "span_id", "parent_span_id", "span_type", "span_name",
#                 "timestamp", "end_time", "agent_id", "metadata",
#                 "span_model", "span_provider", "span_input_tokens", "span_output_tokens",
#                 "span_cache_read_tokens", "span_cache_write_tokens", "span_total_tokens",
#                 "span_outcome" }, ...]
#     }, ...
#   ]
#
# Span type taxonomy (prefix-ordered rules):
#   openclaw.model.*    → model_call
#   openclaw.message.*  → message_event
#   openclaw.session.*  → session_event
#   openclaw.command.*  → command_event
#   openclaw.webhook.*  → webhook_event
#   openclaw.*          → openclaw_event
#   tool.*              → tool_call
#   (anything else)     → span
#
# agent_id derivation (first match wins):
#   openclaw.sessionKey span attr → openclaw.chatId span attr → service.name resource attr → "unknown"
#
# Timestamps arrive as nanosecond strings and are converted to ISO8601.
# OTLP traceIds (32 hex chars) are truncated to 16 chars to match the DB schema.
#
# Usage:
#   results = OtlpNormalizer.call(otlp_json_string)
#   results.each { |r| TelemetryIngester.call(**r) }
#
# Raises OtlpNormalizer::Error on malformed input.
class OtlpNormalizer
  Error = Class.new(StandardError)

  OTLP_ERROR_CODE = 2

  SPAN_TYPE_PREFIXES = [
    ["openclaw.model.",   "model_call"],
    ["openclaw.message.", "message_event"],
    ["openclaw.session.", "session_event"],
    ["openclaw.command.", "command_event"],
    ["openclaw.webhook.", "webhook_event"],
    ["openclaw.tool.",    "tool_call"],
    ["openclaw.request",  "agent_request"],
    ["openclaw.agent.",   "agent_turn"],
    ["openclaw.",         "openclaw_event"],
    ["tool.",             "tool_call"]
  ].freeze

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

    all_entries = spans_by_resource(resource_spans)
    raise Error, "resourceSpans contains no spans" if all_entries.empty?

    grouped = all_entries.group_by { |e| normalize_trace_id(e[:span]["traceId"]) }

    grouped.map do |trace_id, entries|
      raw_spans     = entries.map { |e| e[:span] }
      primary_agent = entries.first[:agent_id]

      trace_line = build_trace_record(raw_spans, trace_id, primary_agent)
      span_lines = entries.map { |e| build_span_record(e[:span], trace_id, e[:resource_attrs]) }

      { trace: trace_line, spans: span_lines }
    end
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

  def spans_by_resource(resource_spans)
    resource_spans.flat_map do |rs|
      resource_attrs = attrs_to_hash(rs.dig("resource", "attributes") || [])
      (rs["scopeSpans"] || []).flat_map { |ss| ss["spans"] || [] }.map do |s|
        span_attrs = attrs_to_hash(s["attributes"] || [])
        agent_id   = resolve_agent_id(span_attrs, resource_attrs)
        { span: s, agent_id: agent_id, resource_attrs: resource_attrs }
      end
    end
  end

  def resolve_agent_id(span_attrs, resource_attrs)
    span_attrs["openclaw.sessionKey"] ||
      span_attrs["openclaw.chatId"] ||
      resource_attrs["service.name"] ||
      "unknown"
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

  def build_trace_record(spans, trace_id, agent_id)
    earliest_nano = spans.map { |s| s["startTimeUnixNano"].to_i }.min
    root_span     = spans.find { |s| s["parentSpanId"].blank? } || spans.first

    {
      "trace_id"   => trace_id,
      "agent_id"   => agent_id,
      "task_name"  => root_span["name"],
      "start_time" => nano_to_iso8601(earliest_nano),
      "status"     => spans.any? { |s| error_in_span?(s) } ? "error" : "success"
    }
  end

  def build_span_record(span, trace_id, resource_attrs)
    span_attrs = attrs_to_hash(span["attributes"] || [])
    agent_id   = resolve_agent_id(span_attrs, resource_attrs)

    {
      "trace_id"               => trace_id,
      "span_id"                => span["spanId"],
      "parent_span_id"         => span["parentSpanId"].presence,
      "span_type"              => resolve_span_type(span["name"]),
      "span_name"              => span["name"],
      "timestamp"              => nano_to_iso8601(span["startTimeUnixNano"]),
      "end_time"               => nano_to_iso8601_or_nil(span["endTimeUnixNano"]),
      "agent_id"               => agent_id,
      "metadata"               => span_attrs,
      "span_model"             => span_attrs["openclaw.model"],
      "span_provider"          => span_attrs["openclaw.provider"],
      "span_input_tokens"      => span_attrs["openclaw.tokens.input"]       || span_attrs["gen_ai.usage.input_tokens"]&.to_i,
      "span_output_tokens"     => span_attrs["openclaw.tokens.output"]      || span_attrs["gen_ai.usage.output_tokens"]&.to_i,
      "span_cache_read_tokens" => span_attrs["openclaw.tokens.cache_read"]  || span_attrs["gen_ai.usage.cache_read_tokens"]&.to_i,
      "span_cache_write_tokens"=> span_attrs["openclaw.tokens.cache_write"] || span_attrs["gen_ai.usage.cache_write_tokens"]&.to_i,
      "span_total_tokens"      => span_attrs["openclaw.tokens.total"]       || span_attrs["gen_ai.usage.total_tokens"]&.to_i,
      "span_outcome"           => resolve_span_outcome(span, span_attrs)
    }
  end

  def resolve_span_type(name)
    SPAN_TYPE_PREFIXES.each do |prefix, type|
      return type if name.to_s.start_with?(prefix)
    end
    "span"
  end

  OUTCOME_ERROR_SET = %w[error failed timeout timed_out].freeze

  def resolve_span_outcome(span, span_attrs)
    return "error" if error_status?(span)
    outcome = span_attrs["openclaw.outcome"]
    OUTCOME_ERROR_SET.include?(outcome) ? "error" : outcome
  end

  def error_in_span?(span)
    return true if error_status?(span)
    outcome = attrs_to_hash(span["attributes"] || [])["openclaw.outcome"]
    OUTCOME_ERROR_SET.include?(outcome)
  end

  def error_status?(span)
    span.dig("status", "code") == OTLP_ERROR_CODE
  end
end
