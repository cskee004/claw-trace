require "rails_helper"

RSpec.describe Span, type: :model do
  let(:trace) do
    Trace.create!(
      trace_id:   "a1b2c3d4e5f6a7b8",
      agent_id:   "support-agent",
      task_name:  "classify_customer_ticket",
      start_time: Time.utc(2026, 4, 2, 12, 0, 0),
      status:     :in_progress
    )
  end

  def valid_attrs(overrides = {})
    {
      trace_id:  trace.trace_id,
      span_id:   "s1",
      span_type: "session_event",
      timestamp: Time.utc(2026, 4, 2, 12, 0, 1),
      agent_id:  "support-agent",
      metadata:  { "task" => "classify_customer_ticket" }
    }.merge(overrides)
  end

  describe "validations" do
    it "is valid with all required attributes" do
      expect(Span.new(valid_attrs)).to be_valid
    end

    it "requires span_id" do
      expect(Span.new(valid_attrs(span_id: nil))).not_to be_valid
    end

    it "requires span_type" do
      expect(Span.new(valid_attrs(span_type: nil))).not_to be_valid
    end

    it "rejects unknown span types" do
      expect(Span.new(valid_attrs(span_type: "unknown_type"))).not_to be_valid
    end

    it "accepts all valid span types" do
      Span::SPAN_TYPES.each_with_index do |span_type, i|
        attrs = valid_attrs(span_id: "s#{i + 1}", span_type: span_type)
        expect(Span.new(attrs)).to be_valid, "expected #{span_type} to be valid"
      end
    end

    it "requires timestamp" do
      expect(Span.new(valid_attrs(timestamp: nil))).not_to be_valid
    end

    it "requires agent_id" do
      expect(Span.new(valid_attrs(agent_id: nil))).not_to be_valid
    end

    it "requires metadata" do
      expect(Span.new(valid_attrs(metadata: nil))).not_to be_valid
    end

    it "enforces span_id uniqueness within the same trace" do
      Span.create!(valid_attrs)
      duplicate = Span.new(valid_attrs)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:span_id]).to be_present
    end

    it "allows the same span_id across different traces" do
      other_trace = Trace.create!(
        trace_id:   "b2c3d4e5f6a7b8c9",
        agent_id:   "code-agent",
        task_name:  "review_pull_request",
        start_time: Time.utc(2026, 4, 2, 13, 0, 0),
        status:     :success
      )
      Span.create!(valid_attrs)
      cross_trace_span = Span.new(valid_attrs(trace_id: other_trace.trace_id))
      expect(cross_trace_span).to be_valid
    end
  end

  describe "associations" do
    it "belongs to a trace via trace_id" do
      span = Span.create!(valid_attrs)
      expect(span.trace).to eq(trace)
    end

    it "is invalid without a matching trace" do
      span = Span.new(valid_attrs(trace_id: "0000000000000000"))
      expect(span).not_to be_valid
      expect(span.errors[:trace]).to be_present
    end

    it "trace has_many spans" do
      Span.create!(valid_attrs(span_id: "s1"))
      Span.create!(valid_attrs(span_id: "s2", span_type: "model_call",
                               metadata: { "model_name" => "claude-sonnet-4-6", "prompt_tokens" => 100 }))
      expect(trace.spans.count).to eq(2)
    end

    it "destroying a trace cascades to its spans" do
      Span.create!(valid_attrs)
      expect { trace.destroy }.to change { Span.count }.by(-1)
    end

    it "parent_span_id is optional" do
      span = Span.create!(valid_attrs(parent_span_id: nil))
      expect(span.parent_span_id).to be_nil
    end

    it "stores parent_span_id when provided" do
      Span.create!(valid_attrs(span_id: "s1"))
      child = Span.create!(valid_attrs(span_id: "s2", span_type: "model_call",
                                       parent_span_id: "s1",
                                       metadata: { "model_name" => "claude-opus-4-6", "prompt_tokens" => 200 }))
      expect(child.parent_span_id).to eq("s1")
    end
  end

  describe "metadata" do
    it "persists and retrieves a metadata hash" do
      meta = { "task" => "classify_customer_ticket" }
      span = Span.create!(valid_attrs(metadata: meta))
      expect(span.reload.metadata).to eq(meta)
    end
  end
end
