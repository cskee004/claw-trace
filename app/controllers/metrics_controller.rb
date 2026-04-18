class MetricsController < ApplicationController
  def index
    all = filtered_scope.order(:metric_name, :metric_key).to_a
    @summaries = all.group_by(&:metric_name).map do |name, series|
      type = series.first.metric_type
      value = if type == "histogram"
        merged_dp = series.each_with_object("bucket_counts" => [], "explicit_bounds" => [], "count" => 0) do |m, acc|
          dp = m.data_points
          acc["count"]  += dp["count"].to_i
          acc["explicit_bounds"] = dp["explicit_bounds"] || acc["explicit_bounds"]
          if acc["bucket_counts"].empty?
            acc["bucket_counts"] = dp["bucket_counts"] || []
          else
            acc["bucket_counts"] = acc["bucket_counts"].zip(dp["bucket_counts"] || []).map { |a, b| a.to_i + b.to_i }
          end
        end
        pcts = HistogramPercentileCalculator.call(
          bucket_counts:   merged_dp["bucket_counts"],
          explicit_bounds: merged_dp["explicit_bounds"]
        )
        { p50: pcts&.dig(:p50), p95: pcts&.dig(:p95), count: merged_dp["count"] }
      else
        series.sum { |m| m.data_points["value"].to_f }
      end
      {
        metric_name:  name,
        metric_type:  type,
        value:        value,
        series_count: series.size,
        updated_at:   series.map(&:updated_at).max
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
    records      = Metric.where(metric_name: @metric_name)
                         .order(:metric_key)
                         .to_a
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
