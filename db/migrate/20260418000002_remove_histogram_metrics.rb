class RemoveHistogramMetrics < ActiveRecord::Migration[8.0]
  def up
    execute "DELETE FROM metrics WHERE metric_type = 'histogram'"
  end

  def down
    # Histogram rows are not recoverable — this migration is intentionally irreversible.
    # Histograms are no longer stored by MetricAggregator.
  end
end
