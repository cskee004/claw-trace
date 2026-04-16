require "rails_helper"

RSpec.describe TraceDurationCalculator do
  def create_trace(overrides = {})
    Trace.create!({
      trace_id:   SecureRandom.hex(8),
      agent_id:   "support-agent",
      task_name:  "test_task",
      start_time: Time.zone.parse("2026-04-03T10:00:00Z"),
      status:     :success
    }.merge(overrides))
  end

  def create_span(trace, timestamp:, overrides: {})
    Span.create!({
      trace_id:       trace.trace_id,
      span_id:        SecureRandom.hex(4),
      parent_span_id: nil,
      span_type:      "model_call",
      timestamp:      timestamp,
      agent_id:       trace.agent_id,
      metadata:       { "span" => true }
    }.merge(overrides))
  end

  describe ".call" do
    it "returns nil when the trace has no spans" do
      trace = create_trace
      expect(described_class.call(trace)).to be_nil
    end

    it "returns 0.0 when the trace has a single span" do
      trace = create_trace
      create_span(trace, timestamp: Time.zone.parse("2026-04-03T10:00:01Z"))
      trace.reload

      expect(described_class.call(trace)).to eq(0.0)
    end

    it "returns elapsed time in milliseconds as a Float" do
      trace = create_trace
      create_span(trace, timestamp: Time.zone.parse("2026-04-03T10:00:00.000Z"))
      create_span(trace, timestamp: Time.zone.parse("2026-04-03T10:00:02.500Z"),
                         overrides: { span_type: "span" })
      trace.reload

      expect(described_class.call(trace)).to eq(2500.0)
    end

    it "uses min and max span timestamps, not insertion order" do
      trace = create_trace
      create_span(trace, timestamp: Time.zone.parse("2026-04-03T10:00:05Z"))
      create_span(trace, timestamp: Time.zone.parse("2026-04-03T10:00:01Z"))
      create_span(trace, timestamp: Time.zone.parse("2026-04-03T10:00:03Z"))
      trace.reload

      # max - min = 5s - 1s = 4000ms
      expect(described_class.call(trace)).to eq(4000.0)
    end
  end

  describe ".call_many" do
    it "returns an empty hash for an empty collection" do
      expect(described_class.call_many([])).to eq({})
    end

    it "returns a hash keyed by trace_id with duration in milliseconds" do
      trace_a = create_trace
      create_span(trace_a, timestamp: Time.zone.parse("2026-04-03T10:00:00Z"))
      create_span(trace_a, timestamp: Time.zone.parse("2026-04-03T10:00:01Z"),
                           overrides: { span_type: "span" })

      trace_b = create_trace
      create_span(trace_b, timestamp: Time.zone.parse("2026-04-03T10:00:00Z"))
      create_span(trace_b, timestamp: Time.zone.parse("2026-04-03T10:00:03Z"),
                           overrides: { span_type: "span" })

      result = described_class.call_many([ trace_a, trace_b ])

      expect(result[trace_a.trace_id]).to eq(1000.0)
      expect(result[trace_b.trace_id]).to eq(3000.0)
    end

    it "excludes traces that have no spans" do
      trace_with_spans    = create_trace
      trace_without_spans = create_trace
      create_span(trace_with_spans, timestamp: Time.zone.parse("2026-04-03T10:00:00Z"))
      create_span(trace_with_spans, timestamp: Time.zone.parse("2026-04-03T10:00:02Z"),
                                    overrides: { span_type: "span" })

      result = described_class.call_many([ trace_with_spans, trace_without_spans ])

      expect(result).to have_key(trace_with_spans.trace_id)
      expect(result).not_to have_key(trace_without_spans.trace_id)
    end

    it "accepts an ActiveRecord::Relation as input" do
      trace = create_trace
      create_span(trace, timestamp: Time.zone.parse("2026-04-03T10:00:00Z"))
      create_span(trace, timestamp: Time.zone.parse("2026-04-03T10:00:01Z"),
                         overrides: { span_type: "span" })

      result = described_class.call_many(Trace.where(trace_id: trace.trace_id))

      expect(result[trace.trace_id]).to eq(1000.0)
    end
  end
end
