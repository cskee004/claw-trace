require "rails_helper"

RSpec.describe MetricPruner do
  def create_metric(timestamp:)
    Metric.create!(
      metric_name:       "gen_ai.client.token.usage",
      metric_type:       "sum",
      timestamp:         timestamp,
      metric_attributes: {},
      data_points:       { "value" => 100, "start_time" => timestamp.iso8601 }
    )
  end

  describe ".call" do
    it "deletes metrics older than retention_days" do
      old_metric = create_metric(timestamp: 31.days.ago)
      MetricPruner.call(retention_days: 30)
      expect(Metric.exists?(old_metric.id)).to be false
    end

    it "preserves metrics within the retention window" do
      recent_metric = create_metric(timestamp: 1.day.ago)
      MetricPruner.call(retention_days: 30)
      expect(Metric.exists?(recent_metric.id)).to be true
    end

    it "returns the count of deleted records" do
      3.times { create_metric(timestamp: 40.days.ago) }
      result = MetricPruner.call(retention_days: 30)
      expect(result[:deleted]).to eq(3)
    end

    it "returns { deleted: 0 } when there is nothing to prune" do
      create_metric(timestamp: 1.day.ago)
      result = MetricPruner.call(retention_days: 30)
      expect(result[:deleted]).to eq(0)
    end

    it "only deletes records older than the given retention_days" do
      old_metric    = create_metric(timestamp: 8.days.ago)
      recent_metric = create_metric(timestamp: 1.day.ago)
      MetricPruner.call(retention_days: 7)
      expect(Metric.exists?(old_metric.id)).to   be false
      expect(Metric.exists?(recent_metric.id)).to be true
    end
  end
end
