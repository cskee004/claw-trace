# Estimates percentiles from OTLP explicit-boundary histogram data.
#
# OTLP histogram buckets work like this:
#   explicit_bounds: [100, 300, 500, 700]  — N boundaries → N+1 buckets
#   bucket_counts:   [10, 40, 60, 30, 10]  — count per bucket
#
# Returns { p50:, p95:, p99: } or nil if there is no data.
class HistogramPercentileCalculator
  PERCENTILES = { p50: 0.50, p95: 0.95, p99: 0.99 }.freeze

  def self.call(bucket_counts:, explicit_bounds:)
    new(bucket_counts: bucket_counts, explicit_bounds: explicit_bounds).call
  end

  def initialize(bucket_counts:, explicit_bounds:)
    @counts = Array(bucket_counts).map(&:to_i)
    @bounds = Array(explicit_bounds).map(&:to_f)
  end

  def call
    return nil if @counts.empty? || @counts.sum.zero?

    total = @counts.sum
    PERCENTILES.transform_values { |fraction| estimate(fraction * total) }
  end

  private

  # Linear interpolation within the bucket that contains rank `target`.
  def estimate(target)
    cumulative = 0
    @counts.each_with_index do |count, i|
      cumulative += count
      next if cumulative < target

      lower        = i.zero? ? 0.0 : @bounds[i - 1]
      upper        = i < @bounds.length ? @bounds[i] : (@bounds.last || 0.0) * 2.0
      prev_cumul   = cumulative - count
      fraction     = count.zero? ? 0.0 : (target - prev_cumul).to_f / count
      return lower + (upper - lower) * fraction
    end

    @bounds.last || 0.0
  end
end
