class Metric < ApplicationRecord
  METRIC_TYPES = %w[sum histogram].freeze

  validates :metric_name, presence: true
  validates :metric_type, presence: true, inclusion: { in: METRIC_TYPES }
  validates :timestamp,   presence: true
  validates :metric_attributes, exclusion: { in: [nil], message: "can't be nil" }
  validates :data_points, exclusion: { in: [nil], message: "can't be nil" }
end
