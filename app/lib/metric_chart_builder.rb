# Builds ApexCharts options and stat data from aggregated Metric records.
#
# With the rolling-aggregation model, each (metric_name, metric_attributes) pair
# is stored as exactly one row. Charts are therefore attribute-comparison views,
# not time-series:
#
#   sum       — horizontal bar chart: one bar per attribute combination
#   histogram — no chart; stats hash carries P50/P95/P99 per series
#   gauge     — same as sum (latest value per series)
#
# Usage:
#   MetricChartBuilder.call(records: records, metric_type: "sum")
#   MetricChartBuilder.call(records: records, metric_type: "histogram")
#
# Returns { options: <ApexCharts hash or {}>, stats: <stat hash or nil> }
class MetricChartBuilder
  def self.call(records:, metric_type:)
    new(records: records, metric_type: metric_type).call
  end

  def initialize(records:, metric_type:)
    @records     = records
    @metric_type = metric_type
  end

  def call
    return { options: {}, stats: nil } if @records.empty?

    case @metric_type
    when "sum", "gauge" then { options: bar_chart_options, stats: sum_stats }
    when "histogram"    then { options: {},                stats: histogram_stats }
    else                     { options: {},                stats: nil }
    end
  end

  private

  # ── Sum / gauge ───────────────────────────────────────────────────────────────

  def bar_chart_options
    labels = @records.map { |r| attrs_label(r.metric_attributes) }
    values = @records.map { |r| r.data_points["value"].to_f.round(4) }

    {
      chart:       { type: "bar", height: [180, @records.size * 48].max,
                     toolbar: { show: false } },
      series:      [{ name: "Total", data: values }],
      xaxis:       { categories: labels },
      plotOptions: { bar: { horizontal: true, borderRadius: 4, barHeight: "60%" } },
      dataLabels:  { enabled: false },
      grid:        { borderColor: "var(--color-surface-2)" },
      colors:      ["var(--color-accent)"],
      tooltip:     { theme: "dark" }
    }
  end

  def sum_stats
    total   = @records.sum { |r| r.data_points["value"].to_f }
    latest  = @records.max_by(&:updated_at)
    {
      type:             @metric_type,
      total:            total,
      series_count:     @records.size,
      latest_timestamp: latest&.updated_at
    }
  end

  # ── Histogram ─────────────────────────────────────────────────────────────────

  def histogram_stats
    series = @records.map do |r|
      dp   = r.data_points
      pcts = HistogramPercentileCalculator.call(
        bucket_counts:   dp["bucket_counts"]   || [],
        explicit_bounds: dp["explicit_bounds"] || []
      )
      {
        label:      attrs_label(r.metric_attributes),
        p50:        pcts&.dig(:p50),
        p95:        pcts&.dig(:p95),
        p99:        pcts&.dig(:p99),
        count:      dp["count"].to_i,
        sum:        dp["sum"].to_f,
        min:        dp["min"],
        max:        dp["max"],
        updated_at: r.updated_at
      }
    end
    { type: "histogram", series: series }
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  def attrs_label(attrs)
    return "(no attributes)" if attrs.blank?

    attrs.map { |k, v| "#{k}: #{v}" }.join(" · ")
  end
end
