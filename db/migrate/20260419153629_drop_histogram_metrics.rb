class DropHistogramMetrics < ActiveRecord::Migration[8.0]
  def up
    Metric.where(metric_type: "histogram").delete_all
  end

  def down
    # irreversible — histogram rows were dropped intentionally
  end
end
