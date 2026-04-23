# Persists telemetry data to the database as Trace + Span records.
#
# Usage:
#   result = TelemetryIngester.call(trace: trace_hash, spans: span_array)
#   # => { trace_id: "a1b2...", spans_ingested: 7 }
#
# trace: — Hash with string keys: trace_id, agent_id, task_name, start_time, status
# spans: — Array of hashes with string keys: span_id, parent_span_id, span_type,
#           span_name, timestamp, agent_id, metadata, span_model, span_provider,
#           span_input_tokens, span_output_tokens, span_cache_read_tokens,
#           span_cache_write_tokens, span_total_tokens, span_outcome
#
# Raises TelemetryIngester::Error on invalid input or validation failure.
# All DB writes are wrapped in a single transaction — all succeed or all roll back.
# After the transaction commits, new span rows and an updated summary panel are
# broadcast to the trace's Turbo Streams channel.
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

    persisted = ActiveRecord::Base.transaction do
      trace = persist_trace(@trace)
      spans = @spans.map { |span| persist_span(span, trace.trace_id) }
      { trace: trace, spans: spans }
    end

    broadcast_new_spans(persisted[:trace], persisted[:spans])
    { trace_id: persisted[:trace].trace_id, spans_ingested: persisted[:spans].length }
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
      trace_id:                trace_id,
      span_id:                 data["span_id"],
      parent_span_id:          data["parent_span_id"],
      span_type:               data["span_type"],
      span_name:               data["span_name"],
      timestamp:               data["timestamp"],
      end_time:                data["end_time"],
      agent_id:                data["agent_id"],
      metadata:                data["metadata"] || {},
      span_model:              data["span_model"],
      span_provider:           data["span_provider"],
      span_input_tokens:       data["span_input_tokens"],
      span_output_tokens:      data["span_output_tokens"],
      span_cache_read_tokens:  data["span_cache_read_tokens"],
      span_cache_write_tokens: data["span_cache_write_tokens"],
      span_total_tokens:       data["span_total_tokens"],
      span_outcome:            data["span_outcome"]
    )
  end

  # Broadcasts each span as an append to the waterfall rows container, then
  # broadcasts a replace of the summary Turbo Frame with updated span count
  # and duration. No-ops if the spans array is empty.
  # Called after the transaction commits — never inside the transaction block.
  def broadcast_new_spans(trace, spans)
    return if spans.empty?

    candidate_times = spans.filter_map(&:end_time) + spans.filter_map(&:timestamp)
    return if candidate_times.empty?

    total_ms = ((candidate_times.max - trace.start_time) * 1000.0).clamp(1.0, Float::INFINITY)

    spans.each do |span|
      locals = {
        span: span,
        depth: compute_span_depth(span),
        latency: span.end_time ? (span.end_time - span.timestamp) * 1000.0 : nil,
        total_ms: total_ms,
        trace_start_time: trace.start_time
      }
      Turbo::StreamsChannel.broadcast_append_to(
        "trace:#{trace.trace_id}",
        target: "waterfall-rows-#{trace.trace_id}",
        partial: "traces/span_row",
        locals: locals
      )
    end

    Turbo::StreamsChannel.broadcast_replace_to(
      "trace:#{trace.trace_id}",
      target: "trace-summary-#{trace.trace_id}",
      partial: "traces/summary",
      locals: {
        trace: trace,
        span_count: trace.spans.count, # all spans on the trace, not just this batch
        total_duration_ms: total_ms,
        estimated_cost_usd: trace.spans.sum(:span_cost_usd).to_f
      }
    )
  end

  # Computes the nesting depth of a span by walking its parent_span_id chain
  # up to the root. Returns 0 for root spans (no parent or parent not in DB).
  # Issues one DB query per level of nesting — acceptable for typical agent
  # traces (2–3 levels deep).
  def compute_span_depth(span)
    depth = 0
    current_parent_id = span.parent_span_id
    while current_parent_id.present? && depth < 20
      parent = Span.find_by(span_id: current_parent_id, trace_id: span.trace_id)
      break unless parent
      depth += 1
      current_parent_id = parent.parent_span_id
    end
    depth
  end
end
