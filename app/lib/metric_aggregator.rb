# Upserts normalized metric rows into the metrics table using running aggregation.
#
# Only sum and gauge metrics are stored — histograms are silently dropped.
# Histogram bucket data represents a time-windowed distribution and is not
# meaningful as a running aggregate across arbitrary time windows.
#
#   sum   — value accumulates (running total)
#   gauge — replaced with the latest value (point-in-time snapshot)
#
# Lookup is keyed on metric_key, a canonical string fingerprint of
# (metric_name, sorted metric_attributes), indexed for O(1) find.
class MetricAggregator
  STORABLE_TYPES = %w[sum gauge].freeze

  def self.call(rows)
    new(rows).call
  end

  def initialize(rows)
    @rows = rows
  end

  def call
    @rows.each { |row| upsert(row) if STORABLE_TYPES.include?(row["metric_type"]) }
  end

  private

  def upsert(row)
    key    = metric_key(row["metric_name"], row["metric_attributes"])
    record = Metric.find_or_initialize_by(metric_key: key)

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
