# Builds ApexCharts options and stat data from aggregated Metric records.
#
# With the rolling-aggregation model, each (metric_name, metric_attributes) pair
# is one row. Charts compare attribute combinations, not time-series:
#
#   sum / gauge — horizontal bar chart: one bar per attribute combination
#
# Histograms are not stored (dropped on ingest) so are not handled here.
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

  # ── Helpers ───────────────────────────────────────────────────────────────────

  def attrs_label(attrs)
    return "(no attributes)" if attrs.blank?

    attrs.map { |k, v| "#{k}: #{v}" }.join(" · ")
  end
end
