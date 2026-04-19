# Reads metric tile data for the dashboard.
#
# Returns a hash keyed by metric name, each value containing:
#   { total: Float, delta_pct: Float|nil }
#
# delta_pct is the percentage change vs the prior period, or nil when no prior
# data exists or prior_range is nil (e.g. custom date ranges).
class MetricStatsService
  TILES = %w[agent.turns.total tool.errors.total].freeze

  def self.call(current_range, prior_range = nil)
    new(current_range, prior_range).call
  end

  def initialize(current_range, prior_range)
    @current_range = current_range
    @prior_range   = prior_range
  end

  def call
    current = totals_for(@current_range)
    return {} if current.empty?

    prior = @prior_range ? totals_for(@prior_range) : {}

    TILES.each_with_object({}) do |name, result|
      current_val = current[name]
      next unless current_val

      prior_val  = prior[name]
      delta_pct  = prior_val&.positive? ? ((current_val - prior_val) / prior_val * 100).round(1) : nil

      result[name] = { total: current_val.round, delta_pct: delta_pct }
    end
  end

  private

  def totals_for(range)
    Metric.where(metric_name: TILES, hour_bucket: range)
          .pluck(:metric_name, :data_points)
          .each_with_object(Hash.new(0.0)) do |(name, dp), acc|
            acc[name] += dp["value"].to_f
          end
  end
end
