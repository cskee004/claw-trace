# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_04_11_174920) do
  create_table "api_keys", force: :cascade do |t|
    t.string "token", null: false
    t.string "agent_type"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["token"], name: "index_api_keys_on_token", unique: true
  end

  create_table "logs", force: :cascade do |t|
    t.string "trace_id"
    t.string "span_id"
    t.string "severity_text"
    t.integer "severity_number"
    t.text "body"
    t.json "log_attributes", default: {}, null: false
    t.datetime "timestamp", null: false
    t.datetime "created_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "updated_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.index ["span_id"], name: "index_logs_on_span_id"
    t.index ["timestamp"], name: "index_logs_on_timestamp"
    t.index ["trace_id"], name: "index_logs_on_trace_id"
  end

  create_table "metrics", force: :cascade do |t|
    t.string "trace_id"
    t.string "metric_name", null: false
    t.string "metric_type", null: false
    t.json "metric_attributes", default: {}, null: false
    t.json "data_points", default: {}, null: false
    t.datetime "timestamp", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["metric_name"], name: "index_metrics_on_metric_name"
    t.index ["timestamp"], name: "index_metrics_on_timestamp"
    t.index ["trace_id"], name: "index_metrics_on_trace_id"
  end

  create_table "spans", force: :cascade do |t|
    t.string "trace_id", null: false
    t.string "span_id", null: false
    t.string "parent_span_id"
    t.string "span_type", null: false
    t.datetime "timestamp", null: false
    t.string "agent_id", null: false
    t.json "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "end_time"
    t.string "span_name"
    t.index ["agent_id"], name: "index_spans_on_agent_id"
    t.index ["span_type"], name: "index_spans_on_span_type"
    t.index ["trace_id", "span_id"], name: "index_spans_on_trace_id_and_span_id", unique: true
    t.index ["trace_id"], name: "index_spans_on_trace_id"
  end

  create_table "traces", force: :cascade do |t|
    t.string "trace_id", null: false
    t.string "agent_id", null: false
    t.string "task_name", null: false
    t.datetime "start_time", null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_traces_on_agent_id"
    t.index ["start_time"], name: "index_traces_on_start_time"
    t.index ["status"], name: "index_traces_on_status"
    t.index ["trace_id"], name: "index_traces_on_trace_id", unique: true
  end

  add_foreign_key "spans", "traces", primary_key: "trace_id"
end
