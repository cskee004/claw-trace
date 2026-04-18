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

  # ── Histogram — silently dropped ─────────────────────────────────────────────

  describe "histogram metric" do
    def histogram_row
      {
        "metric_name"       => "gen_ai.client.operation.duration",
        "metric_type"       => "histogram",
        "trace_id"          => nil,
        "metric_attributes" => {},
        "data_points"       => { "count" => 3, "sum" => 150.0, "bucket_counts" => [1, 2, 0] },
        "timestamp"         => "2026-04-18T12:00:00.000Z"
      }
    end

    it "does not persist histogram rows" do
      expect { MetricAggregator.call([histogram_row]) }.not_to change(Metric, :count)
    end

    it "silently skips histograms even when mixed with sum rows" do
      rows = [sum_row(value: 100), histogram_row]
      expect { MetricAggregator.call(rows) }.to change(Metric, :count).by(1)
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
