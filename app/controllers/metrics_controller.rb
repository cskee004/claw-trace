class MetricsController < ApplicationController
  def index
    @metrics_summary = build_metrics_summary
  end

  def show
    @metric_name = params[:metric_name]
    records      = Metric.where(metric_name: @metric_name).order(:timestamp)
    @metric_type = records.first&.metric_type
    @has_data    = records.any?
    @chart_options = @has_data ? build_chart_options(records, @metric_type) : {}
  end

  private

  def build_metrics_summary
    scope = Metric.all
    scope = scope.where("metric_name LIKE ?", "%#{params[:q]}%")                          if params[:q].present?
    scope = scope.where("json_extract(metric_attributes, '$.model') = ?",    params[:model])    if params[:model].present?
    scope = scope.where("json_extract(metric_attributes, '$.provider') = ?", params[:provider]) if params[:provider].present?
    scope = scope.where("json_extract(metric_attributes, '$.channel') = ?",  params[:channel])  if params[:channel].present?

    scope
      .select("metric_name, metric_type, MAX(timestamp) as latest_timestamp, COUNT(*) as data_point_count")
      .group(:metric_name, :metric_type)
      .order("latest_timestamp DESC")
  end

  def build_chart_options(records, metric_type)
    case metric_type
    when "sum"       then sum_chart_options(records)
    when "histogram" then histogram_chart_options(records)
    else { chart: { type: "line", height: 300 }, series: [], xaxis: { type: "datetime" } }
    end
  end

  def sum_chart_options(records)
    series_data = records.map { |r| { x: r.timestamp.to_i * 1000, y: r.data_points["value"] } }
    {
      chart:  { type: "line", height: 300, zoom: { enabled: false } },
      series: [{ name: "Value", data: series_data }],
      xaxis:  { type: "datetime" },
      stroke: { curve: "smooth" },
      colors: ["#3b82f6"]
    }
  end

  def histogram_chart_options(records)
    p50_data = []; p95_data = []; p99_data = []

    records.each do |r|
      dp   = r.data_points
      pcts = HistogramPercentileCalculator.call(
        bucket_counts:   dp["bucket_counts"]   || [],
        explicit_bounds: dp["explicit_bounds"] || []
      )
      ts = r.timestamp.to_i * 1000
      p50_data << { x: ts, y: pcts&.dig(:p50) }
      p95_data << { x: ts, y: pcts&.dig(:p95) }
      p99_data << { x: ts, y: pcts&.dig(:p99) }
    end

    {
      chart:  { type: "line", height: 300, zoom: { enabled: false } },
      series: [
        { name: "P50", data: p50_data },
        { name: "P95", data: p95_data },
        { name: "P99", data: p99_data }
      ],
      xaxis:  { type: "datetime" },
      stroke: { curve: "smooth" },
      colors: ["#3b82f6", "#f59e0b", "#ef4444"]
    }
  end
end
