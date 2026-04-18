# spec/lib/metric_chart_builder_spec.rb
require "rails_helper"

RSpec.describe MetricChartBuilder do
  let(:now) { Time.utc(2026, 4, 18, 12, 0, 0) }

  def fake_metric(data_points:, attrs: {}, metric_type: "sum")
    instance_double(
      Metric,
      metric_attributes: attrs,
      data_points:       data_points,
      metric_type:       metric_type,
      updated_at:        now
    )
  end

  # ── Sum ───────────────────────────────────────────────────────────────────────

  describe ".call with metric_type: 'sum'" do
    let(:records) do
      [
        fake_metric(data_points: { "value" => 45_230.0 }, attrs: { "model" => "claude-sonnet-4-6" }),
        fake_metric(data_points: { "value" => 12_100.0 }, attrs: { "model" => "claude-opus-4-7"  })
      ]
    end

    subject(:result) { described_class.call(records: records, metric_type: "sum") }

    it "returns a horizontal bar chart" do
      expect(result[:options].dig(:chart, :type)).to eq("bar")
      expect(result[:options].dig(:plotOptions, :bar, :horizontal)).to eq(true)
    end

    it "has one bar per record" do
      expect(result[:options][:series].first[:data].length).to eq(2)
    end

    it "labels bars from metric_attributes" do
      cats = result[:options].dig(:xaxis, :categories)
      expect(cats).to include("model: claude-sonnet-4-6")
      expect(cats).to include("model: claude-opus-4-7")
    end

    it "bar values are the accumulated data_points value" do
      data = result[:options][:series].first[:data]
      expect(data).to eq([45_230.0, 12_100.0])
    end

    it "returns total across all series in stats" do
      expect(result[:stats][:total]).to eq(57_330.0)
    end

    it "returns series_count in stats" do
      expect(result[:stats][:series_count]).to eq(2)
    end

    it "returns type 'sum' in stats" do
      expect(result[:stats][:type]).to eq("sum")
    end
  end

  # ── Gauge ─────────────────────────────────────────────────────────────────────

  describe ".call with metric_type: 'gauge'" do
    let(:records) do
      [fake_metric(data_points: { "value" => 0.73 }, attrs: {}, metric_type: "gauge")]
    end

    subject(:result) { described_class.call(records: records, metric_type: "gauge") }

    it "returns a bar chart" do
      expect(result[:options].dig(:chart, :type)).to eq("bar")
    end

    it "returns type 'gauge' in stats" do
      expect(result[:stats][:type]).to eq("gauge")
    end
  end

  # ── No attributes ─────────────────────────────────────────────────────────────

  describe "metric with no attributes" do
    it "labels the bar '(no attributes)' when attrs is empty" do
      record = fake_metric(data_points: { "value" => 100 }, attrs: {})
      result = described_class.call(records: [record], metric_type: "sum")
      expect(result[:options].dig(:xaxis, :categories)).to eq(["(no attributes)"])
    end
  end

  # ── Unknown metric_type ───────────────────────────────────────────────────────

  describe ".call with unknown metric_type" do
    it "returns empty options" do
      record = fake_metric(data_points: { "value" => 1 })
      result = described_class.call(records: [record], metric_type: "bogus")
      expect(result[:options]).to eq({})
    end

    it "returns nil stats" do
      record = fake_metric(data_points: { "value" => 1 })
      result = described_class.call(records: [record], metric_type: "bogus")
      expect(result[:stats]).to be_nil
    end
  end

  # ── Empty records ─────────────────────────────────────────────────────────────

  describe ".call with empty records" do
    subject(:result) { described_class.call(records: [], metric_type: "sum") }

    it "returns empty options" do
      expect(result[:options]).to eq({})
    end

    it "returns nil stats" do
      expect(result[:stats]).to be_nil
    end
  end
end
