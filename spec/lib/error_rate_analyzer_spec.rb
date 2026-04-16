require "rails_helper"

RSpec.describe ErrorRateAnalyzer do
  def create_trace(overrides = {})
    Trace.create!({
      trace_id:   SecureRandom.hex(8),
      agent_id:   "support-agent",
      task_name:  "test_task",
      start_time: Time.zone.parse("2026-04-03T10:00:00Z"),
      status:     :success
    }.merge(overrides))
  end

  def create_span(trace, span_type: "span", span_outcome: nil, overrides: {})
    Span.create!({
      trace_id:       trace.trace_id,
      span_id:        SecureRandom.hex(4),
      parent_span_id: nil,
      span_type:      span_type,
      span_outcome:   span_outcome,
      timestamp:      Time.zone.parse("2026-04-03T10:00:01Z"),
      agent_id:       trace.agent_id,
      metadata:       { "generated" => true }
    }.merge(overrides))
  end

  # Loads traces from the DB with spans eager-loaded, matching the expected call-site pattern.
  def load_traces(trace_ids)
    Trace.includes(:spans).where(trace_id: trace_ids)
  end

  describe ".call" do
    it "returns 0.0 error_rate and empty list for an empty collection" do
      result = described_class.call([])

      expect(result.error_rate).to eq(0.0)
      expect(result.affected_trace_ids).to be_empty
    end

    it "returns 0.0 error_rate when no traces have error spans" do
      trace = create_trace
      create_span(trace, span_type: "model_call")
      create_span(trace, span_type: "span")

      result = described_class.call(load_traces([trace.trace_id]))

      expect(result.error_rate).to eq(0.0)
      expect(result.affected_trace_ids).to be_empty
    end

    it "returns 100.0 error_rate when all traces have error spans" do
      trace_a = create_trace
      trace_b = create_trace
      create_span(trace_a, span_outcome: "error")
      create_span(trace_b, span_outcome: "error")

      result = described_class.call(load_traces([trace_a.trace_id, trace_b.trace_id]))

      expect(result.error_rate).to eq(100.0)
    end

    it "calculates the correct percentage for a mixed collection" do
      errored = create_trace
      clean_a = create_trace
      clean_b = create_trace
      create_span(errored, span_outcome: "error")
      create_span(clean_a)
      create_span(clean_b)

      result = described_class.call(load_traces([errored, clean_a, clean_b].map(&:trace_id)))

      # 1 of 3 traces errored → 33.333...%
      expect(result.error_rate).to be_within(0.001).of(33.333)
    end

    it "includes the trace_id of each affected trace" do
      errored = create_trace
      clean   = create_trace
      create_span(errored, span_outcome: "error")
      create_span(clean)

      result = described_class.call(load_traces([errored.trace_id, clean.trace_id]))

      expect(result.affected_trace_ids).to contain_exactly(errored.trace_id)
    end

    it "counts a trace with multiple error spans only once" do
      trace = create_trace
      create_span(trace, span_outcome: "error")
      create_span(trace, span_outcome: "error")

      result = described_class.call(load_traces([trace.trace_id]))

      expect(result.error_rate).to eq(100.0)
      expect(result.affected_trace_ids.size).to eq(1)
    end

    it "returns a Result value object with the expected fields" do
      result = described_class.call([])

      expect(result).to respond_to(:error_rate)
      expect(result).to respond_to(:affected_trace_ids)
    end

    it "accepts an ActiveRecord::Relation as input" do
      trace = create_trace
      create_span(trace, span_outcome: "error")

      result = described_class.call(Trace.includes(:spans).where(trace_id: trace.trace_id))

      expect(result.error_rate).to eq(100.0)
      expect(result.affected_trace_ids).to contain_exactly(trace.trace_id)
    end
  end
end
