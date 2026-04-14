# spec/lib/metric_chart_builder_spec.rb
require "rails_helper"

RSpec.describe MetricChartBuilder do
  # Build a lightweight fake Metric record — no DB needed.
  def fake_metric(timestamp:, data_points:, metric_type: "sum")
    instance_double(
      Metric,
      timestamp:   Time.at(timestamp),
      data_points: data_points,
      metric_type: metric_type
    )
  end

  let(:ts1) { 1_712_345_678 }
  let(:ts2) { 1_712_345_738 }

  describe ".call with metric_type: 'sum'" do
    let(:records) do
      [
        fake_metric(timestamp: ts1, data_points: { "value" => 42.0 }),
        fake_metric(timestamp: ts2, data_points: { "value" => 57.5 })
      ]
    end

    subject(:result) { described_class.call(records: records, metric_type: "sum") }

    it "returns a chart type of 'line'" do
      expect(result.dig(:chart, :type)).to eq("line")
    end

    it "returns a single series named 'Value'" do
      expect(result[:series].length).to eq(1)
      expect(result[:series].first[:name]).to eq("Value")
    end

    it "maps records to { x: epoch_ms, y: value } data points" do
      data = result[:series].first[:data]
      expect(data).to eq([
        { x: ts1 * 1000, y: 42.0 },
        { x: ts2 * 1000, y: 57.5 }
      ])
    end

    it "sets xaxis type to 'datetime'" do
      expect(result.dig(:xaxis, :type)).to eq("datetime")
    end
  end

  describe ".call with metric_type: 'histogram'" do
    let(:records) do
      [
        fake_metric(
          timestamp:   ts1,
          metric_type: "histogram",
          data_points: {
            "bucket_counts"   => [10, 40, 60, 30, 10],
            "explicit_bounds" => [100.0, 300.0, 500.0, 700.0]
          }
        ),
        fake_metric(
          timestamp:   ts2,
          metric_type: "histogram",
          data_points: {
            "bucket_counts"   => [0, 0, 100, 0, 0],
            "explicit_bounds" => [100.0, 300.0, 500.0, 700.0]
          }
        )
      ]
    end

    subject(:result) { described_class.call(records: records, metric_type: "histogram") }

    it "returns three series: P50, P95, P99" do
      names = result[:series].map { |s| s[:name] }
      expect(names).to eq(["P50", "P95", "P99"])
    end

    it "each series has one data point per record" do
      result[:series].each do |series|
        expect(series[:data].length).to eq(2)
      end
    end

    it "data points use epoch milliseconds for x" do
      result[:series].each do |series|
        expect(series[:data].first[:x]).to eq(ts1 * 1000)
        expect(series[:data].last[:x]).to eq(ts2 * 1000)
      end
    end

    it "y values are numeric (percentile estimates)" do
      result[:series].each do |series|
        series[:data].each do |point|
          expect(point[:y]).to be_a(Numeric).or be_nil
        end
      end
    end
  end

  describe ".call with unknown metric_type" do
    let(:records) { [fake_metric(timestamp: ts1, data_points: { "value" => 1 })] }

    subject(:result) { described_class.call(records: records, metric_type: "gauge") }

    it "returns a fallback line chart hash" do
      expect(result.dig(:chart, :type)).to eq("line")
    end

    it "returns empty series" do
      expect(result[:series]).to eq([])
    end
  end

  describe ".call with empty records" do
    subject(:result) { described_class.call(records: [], metric_type: "sum") }

    it "returns a fallback line chart hash" do
      expect(result.dig(:chart, :type)).to eq("line")
    end

    it "returns empty series" do
      expect(result[:series]).to eq([])
    end
  end
end
