# Stores a single OTLP metric data point ingested from an OpenClaw agent.
#
# Columns:
#   metric_name       (string)   OTLP metric name (e.g. "gen_ai.client.token.usage")
#   metric_type       (string)   one of METRIC_TYPES — "sum" or "histogram"
#   trace_id          (string)   associated trace identifier, if present in resource attrs
#   metric_attributes (json)     key-value pairs from the OTLP data point attributes
#   data_points       (json)     type-specific scalars: { value, start_time } for sum;
#                                { count, sum, min, max, bucket_counts, explicit_bounds } for histogram
#   timestamp         (datetime) when the data point was recorded
class Metric < ApplicationRecord
  METRIC_TYPES = %w[sum histogram].freeze

  validates :metric_name, presence: true
  validates :metric_type, presence: true, inclusion: { in: METRIC_TYPES }
  validates :timestamp,   presence: true
  validates :metric_attributes, exclusion: { in: [nil], message: "can't be nil" }
  validates :data_points, exclusion: { in: [nil], message: "can't be nil" }
end
