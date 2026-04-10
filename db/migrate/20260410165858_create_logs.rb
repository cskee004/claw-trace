class CreateLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :logs do |t|
      t.string   :trace_id                              # nullable — optional trace correlation
      t.string   :span_id                               # nullable — optional span correlation
      t.string   :severity_text                         # e.g. "INFO", "WARN", "ERROR"
      t.integer  :severity_number                       # OTLP numeric severity (1–24)
      t.text     :body                                  # log message body
      t.json     :log_attributes, null: false, default: {}
      t.datetime :timestamp,      null: false

      t.timestamps null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :logs, :trace_id
    add_index :logs, :span_id
    add_index :logs, :timestamp
  end
end
