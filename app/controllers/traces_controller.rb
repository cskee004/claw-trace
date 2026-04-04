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

  def seed
    result = SimulatorSeeder.call
    if result.errors.empty?
      redirect_to traces_path, notice: "Generated #{result.traces_created} traces."
    else
      redirect_to traces_path, alert: "Generated #{result.traces_created} traces (#{result.errors.size} failed)."
    end
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
