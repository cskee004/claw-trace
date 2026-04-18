# Upserts normalized metric rows into the metrics table using hourly bucket aggregation.
#
# Only sum and gauge metrics are stored — histograms are silently dropped.
#
# One row is stored per (metric_name, metric_attributes, hour_bucket). On each
# ingest the delta is added to the matching hour's running total. This keeps the
# table at O(unique_series × hours_retained) instead of O(raw events).
#
#   sum   — value accumulates within each hour bucket
#   gauge — replaced with the latest value within each hour bucket
class MetricAggregator
  STORABLE_TYPES = %w[sum gauge].freeze

  def self.call(rows)
    new(rows).call
  end

  def initialize(rows)
    @rows   = rows
    @bucket = Time.current.beginning_of_hour
  end

  def call
    @rows.each { |row| upsert(row) if STORABLE_TYPES.include?(row["metric_type"]) }
  end

  private

  def upsert(row)
    key    = metric_key(row["metric_name"], row["metric_attributes"])
    record = Metric.find_or_initialize_by(metric_key: key, hour_bucket: @bucket)

    record.metric_name       = row["metric_name"]
    record.metric_type       = row["metric_type"]
    record.trace_id          = row["trace_id"]
    record.metric_attributes = row["metric_attributes"]
    record.data_points       = merge(record.data_points, row["data_points"], row["metric_type"])
    record.timestamp         = row["timestamp"]
    record.save!
  end

  def merge(existing, incoming, type)
    return incoming if existing.blank?

    case type
    when "sum"
      incoming.merge("value" => existing["value"].to_f + incoming["value"].to_f)
    else
      incoming
    end
  end

  def metric_key(name, attrs)
    canonical = attrs.to_h.sort_by { |k, _| k.to_s }.to_h
    "#{name}:#{canonical.to_json}"
  end
end
