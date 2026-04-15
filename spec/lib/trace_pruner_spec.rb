require "rails_helper"

RSpec.describe TracePruner do
  def create_trace(start_time:)
    Trace.create!(
      trace_id:   SecureRandom.hex(8),
      agent_id:   "test-agent",
      task_name:  "test_task",
      start_time: start_time,
      status:     :success
    )
  end

  def create_span(trace)
    Span.create!(
      trace_id:       trace.trace_id,
      span_id:        SecureRandom.hex(4),
      parent_span_id: nil,
      span_type:      "model_call",
      span_name:      "test_span",
      timestamp:      trace.start_time,
      end_time:       trace.start_time + 1.second,
      agent_id:       trace.agent_id,
      metadata:       {}
    )
  end

  def create_log_for_trace(trace)
    Log.create!(
      trace_id:       trace.trace_id,
      timestamp:      trace.start_time,
      log_attributes: {}
    )
  end

  describe ".call" do
    it "deletes traces older than retention_days" do
      old_trace = create_trace(start_time: 31.days.ago)
      TracePruner.call(retention_days: 30)
      expect(Trace.exists?(old_trace.id)).to be false
    end

    it "deletes spans associated with old traces" do
      old_trace = create_trace(start_time: 31.days.ago)
      span = create_span(old_trace)
      TracePruner.call(retention_days: 30)
      expect(Span.exists?(span.id)).to be false
    end

    it "does NOT delete logs associated with old traces" do
      old_trace = create_trace(start_time: 31.days.ago)
      log = create_log_for_trace(old_trace)
      TracePruner.call(retention_days: 30)
      expect(Log.exists?(log.id)).to be true
    end

    it "preserves traces within the retention window" do
      recent_trace = create_trace(start_time: 1.day.ago)
      TracePruner.call(retention_days: 30)
      expect(Trace.exists?(recent_trace.id)).to be true
    end

    it "preserves spans of recent traces" do
      recent_trace = create_trace(start_time: 1.day.ago)
      span = create_span(recent_trace)
      TracePruner.call(retention_days: 30)
      expect(Span.exists?(span.id)).to be true
    end

    it "returns the count of deleted traces" do
      3.times { create_trace(start_time: 40.days.ago) }
      result = TracePruner.call(retention_days: 30)
      expect(result[:deleted]).to eq(3)
    end

    it "returns { deleted: 0 } when there is nothing to prune" do
      create_trace(start_time: 1.day.ago)
      result = TracePruner.call(retention_days: 30)
      expect(result[:deleted]).to eq(0)
    end

    it "only deletes traces older than the given retention_days" do
      old_trace    = create_trace(start_time: 8.days.ago)
      recent_trace = create_trace(start_time: 1.day.ago)
      TracePruner.call(retention_days: 7)
      expect(Trace.exists?(old_trace.id)).to   be false
      expect(Trace.exists?(recent_trace.id)).to be true
    end
  end
end
