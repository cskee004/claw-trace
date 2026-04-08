class CreateMetrics < ActiveRecord::Migration[8.0]
  def change
    create_table :metrics do |t|
      t.string   :trace_id                           # nullable — optional trace correlation
      t.string   :metric_name,  null: false
      t.string   :metric_type,  null: false          # "sum" or "histogram"
      t.json     :metric_attributes, null: false, default: {}
      t.json     :data_points,  null: false, default: {}
      t.datetime :timestamp,    null: false
      t.timestamps
    end

    add_index :metrics, :trace_id
    add_index :metrics, :metric_name
    add_index :metrics, :timestamp
  end
end
