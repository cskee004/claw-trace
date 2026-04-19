require "rails_helper"

RSpec.describe MetricStatsService do
  def create_metric(name:, value:, hour_bucket:)
    Metric.create!(
      metric_name:       name,
      metric_type:       "sum",
      metric_key:        "#{name}|{}",
      metric_attributes: {},
      data_points:       { "value" => value },
      timestamp:         hour_bucket,
      hour_bucket:       hour_bucket
    )
  end

  let(:current_start) { 2.days.ago.beginning_of_hour }
  let(:current_range) { current_start.. }
  let(:prior_range)   { 4.days.ago..current_start }

  describe ".call" do
    context "with data in both periods" do
      before do
        create_metric(name: "agent.turns.total",  value: 10, hour_bucket: 1.hour.ago.beginning_of_hour)
        create_metric(name: "agent.turns.total",  value: 20, hour_bucket: 3.days.ago.beginning_of_hour)
        create_metric(name: "tool.errors.total",  value: 5,  hour_bucket: 2.hours.ago.beginning_of_hour)
      end

      it "returns totals for the current period" do
        result = described_class.call(current_range, prior_range)
        expect(result["agent.turns.total"][:total]).to eq(10)
        expect(result["tool.errors.total"][:total]).to eq(5)
      end

      it "computes delta_pct vs prior period" do
        result = described_class.call(current_range, prior_range)
        # current=10, prior=20 → -50%
        expect(result["agent.turns.total"][:delta_pct]).to eq(-50.0)
      end

      it "returns nil delta when no prior data for that metric" do
        result = described_class.call(current_range, prior_range)
        expect(result["tool.errors.total"][:delta_pct]).to be_nil
      end
    end

    context "with no current data" do
      it "returns empty hash" do
        expect(described_class.call(current_range, prior_range)).to eq({})
      end
    end

    context "with nil prior_range" do
      before { create_metric(name: "agent.turns.total", value: 5, hour_bucket: 1.hour.ago.beginning_of_hour) }

      it "returns totals with nil delta_pct" do
        result = described_class.call(current_range, nil)
        expect(result["agent.turns.total"][:total]).to eq(5)
        expect(result["agent.turns.total"][:delta_pct]).to be_nil
      end
    end
  end
end
