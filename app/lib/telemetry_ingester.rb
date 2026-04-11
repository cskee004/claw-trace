# Persists telemetry data to the database as Trace + Span records.
#
# Usage:
#   result = TelemetryIngester.call(trace: trace_hash, spans: span_array)
#   # => { trace_id: "a1b2...", spans_ingested: 7 }
#
# trace: — Hash with string keys: trace_id, agent_id, task_name, start_time, status
# spans: — Array of hashes with string keys: span_id, parent_span_id, span_type,
#           name, timestamp, agent_id, metadata
#
# Raises TelemetryIngester::Error on invalid input or validation failure.
# All DB writes are wrapped in a single transaction — all succeed or all roll back.
class TelemetryIngester
  Error = Class.new(StandardError)

  def self.call(trace:, spans:)
    new(trace: trace, spans: spans).call
  end

  def initialize(trace:, spans:)
    @trace = trace
    @spans = spans
  end

  def call
    raise Error, "trace is missing or invalid" unless @trace.is_a?(Hash)
    raise Error, "spans must be an array" unless @spans.is_a?(Array)

    ActiveRecord::Base.transaction do
      trace = persist_trace(@trace)
      spans = @spans.map { |span| persist_span(span, trace.trace_id) }
      { trace_id: trace.trace_id, spans_ingested: spans.length }
    end
  rescue ActiveRecord::RecordInvalid => e
    raise Error, e.message
  end

  private

  def persist_trace(data)
    Trace.create!(
      trace_id:   data["trace_id"],
      agent_id:   data["agent_id"],
      task_name:  data["task_name"],
      start_time: data["start_time"],
      status:     data["status"] || "in_progress"
    )
  end

  def persist_span(data, trace_id)
    Span.create!(
      trace_id:       trace_id,
      span_id:        data["span_id"],
      parent_span_id: data["parent_span_id"],
      span_type:      data["span_type"],
      name:           data["name"],
      timestamp:      data["timestamp"],
      end_time:       data["end_time"],
      agent_id:       data["agent_id"],
      metadata:       data["metadata"] || {}
    )
  end
end
