# Calculates elapsed duration in milliseconds for one or many Trace records.
# Use .call for a single trace (spans must be eager-loaded) or .call_many for
# a collection (issues one grouped SQL query regardless of collection size).
class TraceDurationCalculator
  # Single trace → elapsed milliseconds as Float, or nil if the trace has no spans.
  # Assumes spans are eager-loaded on the trace; does not issue additional queries.
  def self.call(trace)
    new(trace).call
  end

  # Collection of traces → { trace_id => Float (ms) }
  # Traces with no spans are absent from the result hash.
  # Issues a single grouped SQL query regardless of collection size.
  def self.call_many(traces)
    trace_ids = Array(traces).map(&:trace_id)
    return {} if trace_ids.empty?

    epoch = Time.at(0).utc

    rows = Span
      .where(trace_id: trace_ids)
      .where.not(timestamp: epoch)
      .group(:trace_id)
      .pluck(:trace_id, "MIN(timestamp)", "MAX(timestamp)")

    rows.each_with_object({}) do |(trace_id, min_ts, max_ts), hash|
      hash[trace_id] = (Time.parse(max_ts.to_s) - Time.parse(min_ts.to_s)) * 1000.0
    end
  end

  def initialize(trace)
    @trace = trace
  end

  def call
    seconds = @trace.duration
    return nil if seconds.nil?

    seconds * 1000.0
  end
end
