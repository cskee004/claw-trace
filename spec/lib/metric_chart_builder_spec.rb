# spec/lib/metric_chart_builder_spec.rb
require "rails_helper"

RSpec.describe MetricChartBuilder do
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

    # options
    it "returns a chart type of 'line'" do
      expect(result[:options].dig(:chart, :type)).to eq("line")
    end

    it "returns a single series named 'Value'" do
      expect(result[:options][:series].length).to eq(1)
      expect(result[:options][:series].first[:name]).to eq("Value")
    end

    it "maps records to { x: epoch_ms, y: value } data points" do
      data = result[:options][:series].first[:data]
      expect(data).to eq([
        { x: ts1 * 1000, y: 42.0 },
        { x: ts2 * 1000, y: 57.5 }
      ])
    end

    it "sets xaxis type to 'datetime'" do
      expect(result[:options].dig(:xaxis, :type)).to eq("datetime")
    end

    it "uses the accent CSS variable for color" do
      expect(result[:options][:colors]).to eq(["var(--color-accent)"])
    end

    # stats — derived from the last record
    it "returns stats with type 'sum'" do
      expect(result[:stats][:type]).to eq("sum")
    end

    it "returns the latest value from the last record" do
      expect(result[:stats][:latest_value]).to eq(57.5)
    end

    it "returns the latest timestamp from the last record" do
      expect(result[:stats][:latest_timestamp]).to eq(Time.at(ts2))
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

    # options
    it "returns three series: P50, P95, P99" do
      names = result[:options][:series].map { |s| s[:name] }
      expect(names).to eq(["P50", "P95", "P99"])
    end

    it "each series has one data point per record" do
      result[:options][:series].each do |series|
        expect(series[:data].length).to eq(2)
      end
    end

    it "data points use epoch milliseconds for x" do
      result[:options][:series].each do |series|
        expect(series[:data].first[:x]).to eq(ts1 * 1000)
        expect(series[:data].last[:x]).to eq(ts2 * 1000)
      end
    end

    it "y values are numeric (percentile estimates)" do
      result[:options][:series].each do |series|
        series[:data].each do |point|
          expect(point[:y]).to be_a(Numeric).or be_nil
        end
      end
    end

    it "uses CSS variable colors for the three series" do
      expect(result[:options][:colors]).to eq(
        ["var(--color-accent)", "var(--color-warn-fg)", "var(--color-span-error)"]
      )
    end

    # stats — derived from the last record's percentiles
    it "returns stats with type 'histogram'" do
      expect(result[:stats][:type]).to eq("histogram")
    end

    it "returns numeric p50, p95, p99 in stats" do
      expect(result[:stats][:p50]).to be_a(Numeric)
      expect(result[:stats][:p95]).to be_a(Numeric)
      expect(result[:stats][:p99]).to be_a(Numeric)
    end
  end

  describe ".call with unknown metric_type" do
    let(:records) { [fake_metric(timestamp: ts1, data_points: { "value" => 1 })] }

    subject(:result) { described_class.call(records: records, metric_type: "gauge") }

    it "returns a fallback line chart hash in options" do
      expect(result[:options].dig(:chart, :type)).to eq("line")
    end

    it "returns empty series in options" do
      expect(result[:options][:series]).to eq([])
    end

    it "returns nil stats" do
      expect(result[:stats]).to be_nil
    end
  end

  describe ".call with empty records" do
    subject(:result) { described_class.call(records: [], metric_type: "sum") }

    it "returns a fallback line chart hash in options" do
      expect(result[:options].dig(:chart, :type)).to eq("line")
    end

    it "returns empty series in options" do
      expect(result[:options][:series]).to eq([])
    end

    it "returns nil stats" do
      expect(result[:stats]).to be_nil
    end
  end
end
