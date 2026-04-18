class AddMetricKeyToMetrics < ActiveRecord::Migration[8.0]
  def change
    add_column :metrics, :metric_key, :string

    # Existing rows pre-aggregation have no key and can be left null.
    # The unique index uses WHERE metric_key IS NOT NULL so nulls don't conflict.
    add_index :metrics, :metric_key, unique: true,
              where: "metric_key IS NOT NULL",
              name: "index_metrics_on_metric_key"
  end
end
