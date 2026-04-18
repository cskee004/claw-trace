require "rails_helper"

RSpec.describe MetricAggregator do
  def sum_row(name: "gen_ai.client.token.usage", value:, attrs: {})
    {
      "metric_name"       => name,
      "metric_type"       => "sum",
      "trace_id"          => nil,
      "metric_attributes" => attrs,
      "data_points"       => { "value" => value },
      "timestamp"         => "2026-04-18T12:00:00.000Z"
    }
  end

  def histogram_row(count:, sum:, min:, max:, buckets:, bounds: [10, 100], attrs: {})
    {
      "metric_name"       => "gen_ai.client.operation.duration",
      "metric_type"       => "histogram",
      "trace_id"          => nil,
      "metric_attributes" => attrs,
      "data_points"       => {
        "count"           => count,
        "sum"             => sum,
        "min"             => min,
        "max"             => max,
        "bucket_counts"   => buckets,
        "explicit_bounds" => bounds
      },
      "timestamp"         => "2026-04-18T12:00:00.000Z"
    }
  end

  # ── Sum accumulation ──────────────────────────────────────────────────────────

  describe "sum metric" do
    it "creates one record on first ingest" do
      expect { MetricAggregator.call([sum_row(value: 500)]) }
        .to change(Metric, :count).by(1)
    end

    it "does not create a second record for the same metric series" do
      MetricAggregator.call([sum_row(value: 500)])
      expect { MetricAggregator.call([sum_row(value: 300)]) }
        .not_to change(Metric, :count)
    end

    it "accumulates values across ingests" do
      MetricAggregator.call([sum_row(value: 500)])
      MetricAggregator.call([sum_row(value: 300)])
      expect(Metric.last.data_points["value"]).to eq(800.0)
    end

    it "treats different attribute sets as distinct series" do
      MetricAggregator.call([sum_row(value: 100, attrs: { "model" => "claude-sonnet-4-6" })])
      expect {
        MetricAggregator.call([sum_row(value: 200, attrs: { "model" => "claude-opus-4-7" })])
      }.to change(Metric, :count).by(1)
    end

    it "accumulates independently per attribute set" do
      MetricAggregator.call([sum_row(value: 100, attrs: { "model" => "claude-sonnet-4-6" })])
      MetricAggregator.call([sum_row(value: 200, attrs: { "model" => "claude-sonnet-4-6" })])
      MetricAggregator.call([sum_row(value: 50,  attrs: { "model" => "claude-opus-4-7" })])

      sonnet = Metric.find_by("metric_attributes LIKE ?", "%claude-sonnet-4-6%")
      opus   = Metric.find_by("metric_attributes LIKE ?", "%claude-opus-4-7%")
      expect(sonnet.data_points["value"]).to eq(300.0)
      expect(opus.data_points["value"]).to eq(50.0)
    end

    it "attribute key order does not affect series identity" do
      MetricAggregator.call([sum_row(value: 10, attrs: { "a" => "1", "b" => "2" })])
      expect {
        MetricAggregator.call([sum_row(value: 10, attrs: { "b" => "2", "a" => "1" })])
      }.not_to change(Metric, :count)
    end

    it "updates timestamp to the latest ingest" do
      MetricAggregator.call([sum_row(value: 1).merge("timestamp" => "2026-04-18T10:00:00.000Z")])
      MetricAggregator.call([sum_row(value: 1).merge("timestamp" => "2026-04-18T11:00:00.000Z")])
      expect(Metric.last.timestamp.iso8601).to start_with("2026-04-18T11:00:00")
    end
  end

  # ── Histogram accumulation ────────────────────────────────────────────────────

  describe "histogram metric" do
    it "creates one record on first ingest" do
      expect { MetricAggregator.call([histogram_row(count: 3, sum: 150.0, min: 10.0, max: 80.0, buckets: [1, 2, 0])]) }
        .to change(Metric, :count).by(1)
    end

    it "does not create a second record for the same series" do
      MetricAggregator.call([histogram_row(count: 3, sum: 150.0, min: 10.0, max: 80.0, buckets: [1, 2, 0])])
      expect {
        MetricAggregator.call([histogram_row(count: 2, sum: 90.0, min: 20.0, max: 50.0, buckets: [0, 1, 1])])
      }.not_to change(Metric, :count)
    end

    it "accumulates count" do
      MetricAggregator.call([histogram_row(count: 3, sum: 150.0, min: 10.0, max: 80.0, buckets: [1, 2, 0])])
      MetricAggregator.call([histogram_row(count: 2, sum: 90.0,  min: 20.0, max: 50.0, buckets: [0, 1, 1])])
      expect(Metric.last.data_points["count"]).to eq(5)
    end

    it "accumulates sum" do
      MetricAggregator.call([histogram_row(count: 3, sum: 150.0, min: 10.0, max: 80.0, buckets: [1, 2, 0])])
      MetricAggregator.call([histogram_row(count: 2, sum: 90.0,  min: 20.0, max: 50.0, buckets: [0, 1, 1])])
      expect(Metric.last.data_points["sum"]).to eq(240.0)
    end

    it "tracks lifetime min" do
      MetricAggregator.call([histogram_row(count: 1, sum: 80.0, min: 80.0, max: 80.0, buckets: [0, 1, 0])])
      MetricAggregator.call([histogram_row(count: 1, sum: 5.0,  min: 5.0,  max: 5.0,  buckets: [1, 0, 0])])
      expect(Metric.last.data_points["min"]).to eq(5.0)
    end

    it "tracks lifetime max" do
      MetricAggregator.call([histogram_row(count: 1, sum: 5.0,   min: 5.0,   max: 5.0,   buckets: [1, 0, 0])])
      MetricAggregator.call([histogram_row(count: 1, sum: 200.0, min: 200.0, max: 200.0, buckets: [0, 0, 1])])
      expect(Metric.last.data_points["max"]).to eq(200.0)
    end

    it "element-wise adds bucket_counts" do
      MetricAggregator.call([histogram_row(count: 3, sum: 150.0, min: 10.0, max: 80.0, buckets: [1, 2, 0])])
      MetricAggregator.call([histogram_row(count: 2, sum: 90.0,  min: 20.0, max: 50.0, buckets: [0, 1, 1])])
      expect(Metric.last.data_points["bucket_counts"]).to eq([1, 3, 1])
    end
  end

  # ── Multiple rows in one call ─────────────────────────────────────────────────

  describe "batch ingest" do
    it "processes multiple rows in a single call" do
      rows = [
        sum_row(name: "metric.a", value: 10),
        sum_row(name: "metric.b", value: 20)
      ]
      expect { MetricAggregator.call(rows) }.to change(Metric, :count).by(2)
    end
  end

  # ── Empty input ───────────────────────────────────────────────────────────────

  describe "empty input" do
    it "does nothing for an empty array" do
      expect { MetricAggregator.call([]) }.not_to change(Metric, :count)
    end
  end
end
