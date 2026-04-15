# Computes aggregate stats for a single agent across all their traces.
# traces must have spans eager-loaded (Trace.includes(:spans)) — ErrorRateAnalyzer
# and top_tools computation both read trace.spans without issuing extra queries.
class AgentAggregator
  Result = Data.define(
    :agent_id, :total_runs, :success_count, :error_count,
    :error_rate, :avg_duration_ms, :last_seen, :top_tools
  )

  def self.call(agent_id:, traces:)
    new(agent_id: agent_id, traces: traces).call
  end

  def initialize(agent_id:, traces:)
    @agent_id = agent_id
    @traces   = Array(traces)
  end

  def call
    return empty_result if @traces.empty?

    durations    = TraceDurationCalculator.call_many(@traces)
    error_result = ErrorRateAnalyzer.call(@traces)
    all_spans    = @traces.flat_map(&:spans)
    top_tools    = ToolCallAnalyzer.call(all_spans)
                     .sort_by { |_, v| -v[:calls] }
                     .first(5)
                     .to_h

    # Denominator is traces-with-spans only; spanless traces are excluded from the average.
    avg_ms = durations.empty? ? nil : durations.values.sum / durations.values.size.to_f

    Result.new(
      agent_id:        @agent_id,
      total_runs:      @traces.size,
      success_count:   @traces.count(&:success?),
      error_count:     @traces.count(&:error?),
      error_rate:      error_result.error_rate.round(1),
      avg_duration_ms: avg_ms&.round(1),
      last_seen:       @traces.map(&:start_time).max,
      top_tools:       top_tools
    )
  end

  private

  def empty_result
    Result.new(
      agent_id:        @agent_id,
      total_runs:      0,
      success_count:   0,
      error_count:     0,
      error_rate:      0.0,
      avg_duration_ms: nil,
      last_seen:       nil,
      top_tools:       {}
    )
  end
end
