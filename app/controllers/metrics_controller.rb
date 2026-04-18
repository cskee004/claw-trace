class MetricsController < ApplicationController
  include TimeWindowFilter

  def index
    all = filtered_scope.where(hour_bucket: time_range)
                        .order(:metric_name, :metric_key, :hour_bucket)
                        .to_a
    @summaries = all.group_by(&:metric_name).map do |name, rows|
      {
        metric_name:  name,
        metric_type:  rows.first.metric_type,
        total:        rows.sum { |m| m.data_points["value"].to_f },
        series_count: rows.map(&:metric_key).uniq.size,
        updated_at:   rows.map(&:updated_at).max
      }
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
    spans            = Span.where(span_type: "tool_call")
                           .where("timestamp >= ?", 24.hours.ago)
    @tool_calls_data = ToolCallAnalyzer.call(spans)
    @chart_options   = @tool_calls_data.any? ? tool_calls_chart_options : {}
    render partial: "tool_calls_chart"
  end

  private

  def load_chart_data
    rows = Metric.where(metric_name: @metric_name)
                 .where(hour_bucket: time_range)
                 .order(:metric_key, :hour_bucket)
                 .to_a

    @metric_type = rows.first&.metric_type
    @has_data    = rows.any?

    if @has_data
      # Collapse hour buckets into one aggregated record per attribute series.
      aggregated = rows.group_by(&:metric_key).map do |_key, buckets|
        first = buckets.first
        OpenStruct.new(
          metric_attributes: first.metric_attributes,
          metric_type:       first.metric_type,
          data_points:       { "value" => buckets.sum { |r| r.data_points["value"].to_f } },
          updated_at:        buckets.map(&:updated_at).max
        )
      end

      result         = MetricChartBuilder.call(records: aggregated, metric_type: @metric_type)
      @chart_options = result[:options]
      @chart_stats   = result[:stats]
    else
      @chart_options = {}
      @chart_stats   = nil
    end
  end

  def filtered_scope
    scope = Metric.all
    scope = scope.where("metric_name LIKE ?", "%#{params[:q]}%")                               if params[:q].present?
    scope = scope.where("json_extract(metric_attributes, '$.model') = ?",    params[:model])    if params[:model].present?
    scope = scope.where("json_extract(metric_attributes, '$.provider') = ?", params[:provider]) if params[:provider].present?
    scope = scope.where("json_extract(metric_attributes, '$.channel') = ?",  params[:channel])  if params[:channel].present?
    scope
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
      colors:      ["var(--color-accent)", "var(--color-success-fg)"],
      plotOptions: { bar: { borderRadius: 4, columnWidth: "50%" } }
    }
  end
end
