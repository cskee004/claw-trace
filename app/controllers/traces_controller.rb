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
    @logs_by_span_id = Log.where(span_id: @spans.map(&:span_id)).order(:timestamp).group_by(&:span_id)
    @estimated_cost_usd = @trace.spans.sum(:span_cost_usd).to_f
  end

  def preview
    @trace = Trace.find_by!(trace_id: params[:id])
    spans  = @trace.spans.order(:timestamp)
    @span_latencies = compute_latencies_ms(spans)
    @total_duration_ms = TraceDurationCalculator.call(@trace)
    @spans = TracesHelper.dfs_ordered_spans(spans.to_a)
    @log_counts = Log.where(span_id: @spans.map(&:span_id)).group(:span_id).count
    render partial: "span_preview"
  end

  def summary
    @trace = Trace.find_by!(trace_id: params[:id])
    span_count = @trace.spans.count
    total_duration_ms = TraceDurationCalculator.call(@trace)
    estimated_cost_usd = @trace.spans.sum(:span_cost_usd).to_f
    render partial: "summary", locals: {
      trace: @trace,
      span_count: span_count,
      total_duration_ms: total_duration_ms,
      estimated_cost_usd: estimated_cost_usd
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
    spans          = @trace.spans.where(span_type: "tool_call")
    data           = ToolCallAnalyzer.call(spans)
    @chart_options = data.any? ? trace_tool_calls_chart_options(data) : {}
    render partial: "tool_calls_chart"
  end

  def waterfall
    @trace = Trace.find_by!(trace_id: params[:id])
    spans = @trace.spans.order(:timestamp)
    span_latencies = compute_latencies_ms(spans)
    total_duration_ms = TraceDurationCalculator.call(@trace)
    ordered_spans = TracesHelper.dfs_ordered_spans(spans.to_a)
    logs_by_span_id = Log.where(span_id: ordered_spans.map(&:span_id)).order(:timestamp).group_by(&:span_id)
    render partial: "waterfall", locals: {
      trace: @trace,
      spans: ordered_spans,
      span_latencies: span_latencies,
      total_duration_ms: total_duration_ms,
      logs_by_span_id: logs_by_span_id
    }
  end

  def logs
    @trace     = Trace.find_by!(trace_id: params[:id])
    all_logs   = Log.where(trace_id: @trace.trace_id).order(timestamp: :asc).to_a
    all_logs   = all_logs.select { |l| l.span_id == params[:span_id] } if params[:span_id].present?

    subsystems = all_logs
                   .filter_map { |l| l.log_attributes.is_a?(Hash) ? l.log_attributes["openclaw.subsystem"] : nil }
                   .uniq
                   .sort

    subsystem  = params[:subsystem].presence
    trace_logs = if subsystem
                   all_logs.select { |l| (l.log_attributes || {})["openclaw.subsystem"] == subsystem }
                 else
                   all_logs
                 end

    render partial: "all_logs", locals: {
      trace_id:   @trace.trace_id,
      logs:       trace_logs,
      subsystems: subsystems,
      subsystem:  subsystem,
      span_id:    params[:span_id].presence,
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
    spans.each_with_object({}) do |span, h|
      next unless span.end_time
      h[span.span_id] = (span.end_time - span.timestamp) * 1000.0
    end
  end
end
