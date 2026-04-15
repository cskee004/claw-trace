require "rails_helper"

RSpec.describe LogPruner do
  def create_log(timestamp:)
    Log.create!(
      timestamp:      timestamp,
      log_attributes: {}
    )
  end

  describe ".call" do
    it "deletes log records older than retention_days" do
      old_log = create_log(timestamp: 31.days.ago)
      LogPruner.call(retention_days: 30)
      expect(Log.exists?(old_log.id)).to be false
    end

    it "preserves log records within the retention window" do
      recent_log = create_log(timestamp: 1.day.ago)
      LogPruner.call(retention_days: 30)
      expect(Log.exists?(recent_log.id)).to be true
    end

    it "returns the count of deleted records" do
      3.times { create_log(timestamp: 40.days.ago) }
      result = LogPruner.call(retention_days: 30)
      expect(result[:deleted]).to eq(3)
    end

    it "returns { deleted: 0 } when there is nothing to prune" do
      create_log(timestamp: 1.day.ago)
      result = LogPruner.call(retention_days: 30)
      expect(result[:deleted]).to eq(0)
    end

    it "only deletes records older than the given retention_days" do
      old_log    = create_log(timestamp: 8.days.ago)
      recent_log = create_log(timestamp: 1.day.ago)
      LogPruner.call(retention_days: 7)
      expect(Log.exists?(old_log.id)).to   be false
      expect(Log.exists?(recent_log.id)).to be true
    end
  end
end
