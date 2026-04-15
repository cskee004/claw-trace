class TracesController < ApplicationController
  def index
    @traces = session_id.present? ? traces_for_session(session_id) : Trace.order(start_time: :desc)
    @durations = TraceDurationCalculator.call_many(@traces)
  end

  def reset
    Span.delete_all
    Log.delete_all
    Metric.delete_all
    Trace.delete_all
    redirect_to traces_path, notice: "All data cleared."
  end

  def show
    @trace = Trace.find_by!(trace_id: params[:id])
    spans = @trace.spans.order(:timestamp)
    @span_latencies = compute_latencies_ms(spans)
    @total_duration_ms = TraceDurationCalculator.call(@trace)
    @spans = TracesHelper.dfs_ordered_spans(spans.to_a)
  end

  def preview
    @trace = Trace.find_by!(trace_id: params[:id])
    spans  = @trace.spans.order(:timestamp)
    @span_latencies = compute_latencies_ms(spans)
    @total_duration_ms = TraceDurationCalculator.call(@trace)
    @spans = TracesHelper.dfs_ordered_spans(spans.to_a)
    render partial: "span_preview"
  end

  def summary
    @trace = Trace.find_by!(trace_id: params[:id])
    span_count = @trace.spans.count
    total_duration_ms = TraceDurationCalculator.call(@trace)
    render partial: "summary", locals: {
      trace: @trace,
      span_count: span_count,
      total_duration_ms: total_duration_ms
    }
  end

  def span_chart
    @trace        = Trace.find_by!(trace_id: params[:id])
    spans         = @trace.spans.order(:timestamp)
    ordered_spans = TracesHelper.dfs_ordered_spans(spans.to_a)
    latencies     = compute_latencies_ms(spans)
    @chart_options = SpanChartBuilder.call(spans: ordered_spans, latencies: latencies)[:options]
    render partial: "span_chart"
  end

  def tool_calls_chart
    @trace         = Trace.find_by!(trace_id: params[:id])
    spans          = @trace.spans.where(span_type: "tool_result")
    data           = ToolCallAnalyzer.call(spans)
    @chart_options = data.any? ? trace_tool_calls_chart_options(data) : {}
    render partial: "tool_calls_chart"
  end

  def error_chart
    traces_by_day = Trace.includes(:spans)
                         .where(start_time: 30.days.ago..)
                         .order(:start_time)
                         .group_by { |t| t.start_time.to_date }

    series_data = traces_by_day.map do |date, day_traces|
      result = ErrorRateAnalyzer.call(day_traces)
      { x: date.to_time.to_i * 1000, y: result.error_rate.round(1) }
    end

    @chart_options = {
      chart:  { type: "line", height: 240, toolbar: { show: false }, zoom: { enabled: false } },
      series: [{ name: "Error Rate %", data: series_data }],
      xaxis:  { type: "datetime" },
      yaxis:  { min: 0, max: 100, title: { text: "%" } },
      stroke: { curve: "smooth" },
      colors: ["var(--color-span-error)"]
    }
    render partial: "error_chart"
  end

  def waterfall
    @trace = Trace.find_by!(trace_id: params[:id])
    spans = @trace.spans.order(:timestamp)
    span_latencies = compute_latencies_ms(spans)
    total_duration_ms = TraceDurationCalculator.call(@trace)
    ordered_spans = TracesHelper.dfs_ordered_spans(spans.to_a)
    render partial: "waterfall", locals: {
      trace: @trace,
      spans: ordered_spans,
      span_latencies: span_latencies,
      total_duration_ms: total_duration_ms
    }
  end

  private

  def session_id
    params[:session_id].presence
  end

  def traces_for_session(sid)
    matching_ids = Span.where(session_id_condition, sid).distinct.pluck(:trace_id)
    Trace.where(trace_id: matching_ids).order(start_time: :desc)
  end

  def session_id_condition
    if ActiveRecord::Base.connection.adapter_name.start_with?("SQLite")
      "json_extract(metadata, '$.\"agent.session.id\"') = ?"
    else
      "metadata->>'agent.session.id' = ?"
    end
  end

  def trace_tool_calls_chart_options(data)
    sorted        = data.sort_by { |_, v| -v[:calls] }
    tool_names    = sorted.map(&:first)
    call_counts   = sorted.map { |_, v| v[:calls] }
    success_rates = sorted.map { |_, v| (v[:success_rate] * 100).round(1) }

    {
      chart:       { type: "bar", height: 300, toolbar: { show: false } },
      series:      [
        { name: "Calls",          data: call_counts },
        { name: "Success Rate %", data: success_rates }
      ],
      xaxis:       { categories: tool_names },
      yaxis:       [
        { title: { text: "Calls" } },
        { opposite: true, title: { text: "Success %" }, max: 100 }
      ],
      colors:      ["var(--color-accent)", "var(--color-success-fg)"],
      plotOptions: { bar: { borderRadius: 4, columnWidth: "50%" } }
    }
  end

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
