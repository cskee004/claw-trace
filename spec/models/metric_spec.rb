require "rails_helper"

RSpec.describe Metric, type: :model do
  def valid_attrs(overrides = {})
    {
      metric_name: "gen_ai.client.token.usage",
      metric_type: "sum",
      metric_attributes:  { "gen_ai.system" => "anthropic", "gen_ai.response.model" => "claude-sonnet-4-6" },
      data_points: { "value" => 1200, "start_time" => "2026-04-08T11:00:00Z" },
      timestamp:   Time.utc(2026, 4, 8, 11, 0, 0)
    }.merge(overrides)
  end

  describe "validations" do
    it "is valid with all required attributes" do
      expect(Metric.new(valid_attrs)).to be_valid
    end

    it "requires metric_name" do
      expect(Metric.new(valid_attrs(metric_name: nil))).not_to be_valid
    end

    it "requires metric_type" do
      expect(Metric.new(valid_attrs(metric_type: nil))).not_to be_valid
    end

    it "rejects unknown metric types" do
      expect(Metric.new(valid_attrs(metric_type: "histogram"))).not_to be_valid
    end

    it "accepts all valid metric types" do
      Metric::METRIC_TYPES.each do |metric_type|
        expect(Metric.new(valid_attrs(metric_type: metric_type))).to be_valid,
          "expected #{metric_type} to be valid"
      end
    end

    it "requires timestamp" do
      expect(Metric.new(valid_attrs(timestamp: nil))).not_to be_valid
    end

    it "rejects nil attributes" do
      expect(Metric.new(valid_attrs(metric_attributes: nil))).not_to be_valid
    end

    it "accepts an empty attributes hash" do
      expect(Metric.new(valid_attrs(metric_attributes: {}))).to be_valid
    end

    it "rejects nil data_points" do
      expect(Metric.new(valid_attrs(data_points: nil))).not_to be_valid
    end

    it "accepts an empty data_points hash" do
      expect(Metric.new(valid_attrs(data_points: {}))).to be_valid
    end

    it "allows trace_id to be nil" do
      expect(Metric.new(valid_attrs(trace_id: nil))).to be_valid
    end

    it "allows trace_id to reference a trace" do
      expect(Metric.new(valid_attrs(trace_id: "a1b2c3d4e5f6a7b8"))).to be_valid
    end
  end

  describe "JSON columns" do
    it "persists and retrieves a nested metric_attributes hash" do
      attrs = { "gen_ai.system" => "anthropic", "gen_ai.response.model" => "claude-sonnet-4-6" }
      metric = Metric.create!(valid_attrs(metric_attributes: attrs))
      expect(metric.reload.metric_attributes).to eq(attrs)
    end

    it "persists and retrieves sum data_points" do
      points = { "value" => 4200, "start_time" => "2026-04-08T11:00:00Z" }
      metric = Metric.create!(valid_attrs(data_points: points))
      expect(metric.reload.data_points).to eq(points)
    end

    it "persists and retrieves gauge data_points" do
      points = { "value" => 0.73 }
      metric = Metric.create!(valid_attrs(metric_type: "gauge", data_points: points))
      expect(metric.reload.data_points).to eq(points)
    end
  end
end
