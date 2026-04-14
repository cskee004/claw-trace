# app/lib/metric_chart_builder.rb
#
# Builds ApexCharts options and stat-strip data from a collection of Metric records.
#
# Usage:
#   MetricChartBuilder.call(records: records, metric_type: "sum")
#   MetricChartBuilder.call(records: records, metric_type: "histogram")
#
# Returns { options: <ApexCharts hash>, stats: <stat hash or nil> }
class MetricChartBuilder
  FALLBACK_OPTIONS = {
    chart:  { type: "line", height: 300 },
    series: [],
    xaxis:  { type: "datetime" }
  }.freeze

  def self.call(records:, metric_type:)
    new(records: records, metric_type: metric_type).call
  end

  def initialize(records:, metric_type:)
    @records     = records
    @metric_type = metric_type
  end

  def call
    return { options: FALLBACK_OPTIONS.dup, stats: nil } if @records.empty?

    case @metric_type
    when "sum"
      { options: sum_chart_options, stats: sum_stats }
    when "histogram"
      { options: histogram_chart_options, stats: histogram_stats }
    else
      { options: FALLBACK_OPTIONS.dup, stats: nil }
    end
  end

  private

  def sum_chart_options
    series_data = @records.map { |r| { x: r.timestamp.to_i * 1000, y: r.data_points["value"] } }
    {
      chart:  { type: "line", height: 300, zoom: { enabled: false } },
      series: [{ name: "Value", data: series_data }],
      xaxis:  { type: "datetime" },
      stroke: { curve: "smooth" },
      colors: ["#3b82f6"]
    }
  end

  def sum_stats
    latest = @records.last
    {
      type:             "sum",
      latest_value:     latest.data_points["value"],
      latest_timestamp: latest.timestamp
    }
  end

  def histogram_chart_options
    p50_data = []
    p95_data = []
    p99_data = []

    @records.each do |r|
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

  def histogram_stats
    latest = @records.last
    dp     = latest.data_points
    pcts   = HistogramPercentileCalculator.call(
      bucket_counts:   dp["bucket_counts"]   || [],
      explicit_bounds: dp["explicit_bounds"] || []
    )
    {
      type: "histogram",
      p50:  pcts&.dig(:p50),
      p95:  pcts&.dig(:p95),
      p99:  pcts&.dig(:p99)
    }
  end
end
