class TracesController < ApplicationController
  def index
    @traces = Trace.order(start_time: :desc)
    @durations = TraceDurationCalculator.call_many(@traces)
  end

  def show
    @trace = Trace.find_by!(trace_id: params[:id])
    @spans = @trace.spans.order(:timestamp)
    @span_latencies = compute_latencies_ms(@spans)
    @total_duration_ms = TraceDurationCalculator.call(@trace)
  end

  private

  def compute_latencies_ms(spans)
    latencies = {}
    spans.each_cons(2) do |current, nxt|
      latencies[current.span_id] = (nxt.timestamp - current.timestamp) * 1000.0
    end
    latencies
  end
end
