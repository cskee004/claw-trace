class MetricsController < ApplicationController
  def index
    @metric_names = build_metrics_summary.map do |m|
      { metric_name: m.metric_name, metric_type: m.metric_type }
    end
  end

  def show
    @metric_name = params[:metric_name]
    load_chart_data
  end

  def chart
    @metric_name = params[:metric_name]
    load_chart_data
    render partial: "chart"
  end

  def tool_calls_chart
    spans            = Span.where(span_type: "tool_result")
                           .where("timestamp >= ?", 24.hours.ago)
    @tool_calls_data = ToolCallAnalyzer.call(spans)
    @chart_options   = @tool_calls_data.any? ? tool_calls_chart_options : {}
    render partial: "tool_calls_chart"
  end

  private

  def load_chart_data
    records      = Metric.where(metric_name: @metric_name).order(:timestamp).to_a
    @metric_type = records.first&.metric_type
    @has_data    = records.any?
    if @has_data
      result         = MetricChartBuilder.call(records: records, metric_type: @metric_type)
      @chart_options = result[:options]
      @chart_stats   = result[:stats]
    else
      @chart_options = {}
      @chart_stats   = nil
    end
  end

  def tool_calls_chart_options
    sorted        = @tool_calls_data.sort_by { |_, v| -v[:calls] }
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
      colors:      ["#3b82f6", "#22c55e"],
      plotOptions: { bar: { borderRadius: 4, columnWidth: "50%" } }
    }
  end

  def build_metrics_summary
    scope = Metric.all
    scope = scope.where("metric_name LIKE ?", "%#{params[:q]}%")                               if params[:q].present?
    scope = scope.where("json_extract(metric_attributes, '$.model') = ?",    params[:model])    if params[:model].present?
    scope = scope.where("json_extract(metric_attributes, '$.provider') = ?", params[:provider]) if params[:provider].present?
    scope = scope.where("json_extract(metric_attributes, '$.channel') = ?",  params[:channel])  if params[:channel].present?

    scope
      .select("metric_name, metric_type, MAX(timestamp) as latest_timestamp, COUNT(*) as data_point_count")
      .group(:metric_name, :metric_type)
      .order("latest_timestamp DESC")
  end
end
