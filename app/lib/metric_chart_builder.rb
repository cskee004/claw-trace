# app/lib/metric_chart_builder.rb
#
# Builds ApexCharts options hashes from a collection of Metric records.
#
# Usage:
#   MetricChartBuilder.call(records: records, metric_type: "sum")
#   MetricChartBuilder.call(records: records, metric_type: "histogram")
#
# Returns a plain Ruby hash compatible with ApexCharts JS.
class MetricChartBuilder
  FALLBACK = {
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
    return FALLBACK.dup if @records.empty?

    case @metric_type
    when "sum"       then sum_chart_options
    when "histogram" then histogram_chart_options
    else                  FALLBACK.dup
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
end
