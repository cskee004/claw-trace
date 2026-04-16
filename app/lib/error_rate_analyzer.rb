# Computes error rate across a collection of Trace records.
# A trace is considered errored if it contains at least one span with span_outcome "error".
# Spans must be eager-loaded (e.g. Trace.includes(:spans)) to avoid N+1 queries.
class ErrorRateAnalyzer
  Result = Data.define(:error_rate, :affected_trace_ids)

  # traces — Array or ActiveRecord::Relation of Trace records.
  # Spans must be eager-loaded on each trace (e.g. Trace.includes(:spans))
  # to avoid N+1 queries.
  #
  # Returns a Result with:
  #   error_rate         — Float percentage (0.0–100.0) of traces containing an error span
  #   affected_trace_ids — Array of trace_id strings for traces with at least one error span
  def self.call(traces)
    new(traces).call
  end

  def initialize(traces)
    @traces = Array(traces)
  end

  def call
    return Result.new(error_rate: 0.0, affected_trace_ids: []) if @traces.empty?

    errored = @traces.select { |t| error_trace?(t) }

    Result.new(
      error_rate:         (errored.size.to_f / @traces.size) * 100.0,
      affected_trace_ids: errored.map(&:trace_id)
    )
  end

  private

  def error_trace?(trace)
    trace.spans.any? { |s| s.span_outcome == "error" }
  end
end
