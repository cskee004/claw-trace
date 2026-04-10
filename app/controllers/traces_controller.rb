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

    # For spans with end_time, use actual measured duration.
    # For spans without end_time, fall back to time-until-next-span-starts.
    spans.each_cons(2) do |current, nxt|
      latencies[current.span_id] = if current.end_time
        (current.end_time - current.timestamp) * 1000.0
      else
        (nxt.timestamp - current.timestamp) * 1000.0
      end
    end

    # The last span is excluded from each_cons(2); include it if it has end_time.
    if (last = spans.last) && last.end_time
      latencies[last.span_id] = (last.end_time - last.timestamp) * 1000.0
    end

    latencies
  end
end
