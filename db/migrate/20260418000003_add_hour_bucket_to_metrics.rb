class AddHourBucketToMetrics < ActiveRecord::Migration[8.0]
  def up
    add_column :metrics, :hour_bucket, :datetime

    # Remove the single-column unique index — uniqueness now requires the bucket too.
    remove_index :metrics, name: "index_metrics_on_metric_key"

    # Composite unique: one row per (series, hour).
    add_index :metrics, %i[metric_key hour_bucket], unique: true,
              where: "metric_key IS NOT NULL AND hour_bucket IS NOT NULL",
              name: "index_metrics_on_metric_key_and_hour_bucket"

    add_index :metrics, :hour_bucket, name: "index_metrics_on_hour_bucket"

    # Purge rows written under the old single-row model (null hour_bucket).
    # They carry lifetime totals with no time context and will never be queried.
    execute "DELETE FROM metrics WHERE hour_bucket IS NULL"
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "Cannot restore rows deleted by the hour_bucket NULL purge in `up`."
  end
end
