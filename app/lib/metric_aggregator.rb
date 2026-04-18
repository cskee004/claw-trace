# Upserts normalized metric rows into the metrics table using running aggregation.
#
# Instead of appending every data point, each unique (metric_name, metric_attributes)
# pair is stored as a single row and updated in place on every ingest:
#
#   sum     — value accumulates (running total)
#   histogram — count/sum/bucket_counts accumulate; min/max track lifetime extremes
#   gauge   — replaced with the latest value (point-in-time snapshot)
#
# Lookup is keyed on metric_key, a canonical string fingerprint of
# (metric_name, sorted metric_attributes), indexed for O(1) find.
class MetricAggregator
  def self.call(rows)
    new(rows).call
  end

  def initialize(rows)
    @rows = rows
  end

  def call
    @rows.each { |row| upsert(row) }
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
    when "histogram"
      {
        "count"           => existing["count"].to_i + incoming["count"].to_i,
        "sum"             => existing["sum"].to_f   + incoming["sum"].to_f,
        "min"             => [existing["min"], incoming["min"]].compact.min,
        "max"             => [existing["max"], incoming["max"]].compact.max,
        "bucket_counts"   => merge_buckets(existing["bucket_counts"], incoming["bucket_counts"]),
        "explicit_bounds" => incoming["explicit_bounds"] || existing["explicit_bounds"]
      }.compact
    else
      incoming
    end
  end

  def merge_buckets(existing, incoming)
    return incoming if existing.nil?
    return existing if incoming.nil?

    existing.zip(incoming).map { |a, b| a.to_i + b.to_i }
  end

  def metric_key(name, attrs)
    canonical = attrs.to_h.sort_by { |k, _| k.to_s }.to_h
    "#{name}:#{canonical.to_json}"
  end
end
