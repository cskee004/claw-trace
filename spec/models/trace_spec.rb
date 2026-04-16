require "rails_helper"

RSpec.describe Trace, type: :model do
  def valid_attrs(overrides = {})
    {
      trace_id:   "a1b2c3d4e5f6a7b8",
      agent_id:   "support-agent",
      task_name:  "classify_customer_ticket",
      start_time: Time.utc(2026, 4, 2, 12, 0, 0),
      status:     :in_progress
    }.merge(overrides)
  end

  describe "validations" do
    it "is valid with all required attributes" do
      expect(Trace.new(valid_attrs)).to be_valid
    end

    describe "trace_id" do
      it "requires presence" do
        expect(Trace.new(valid_attrs(trace_id: nil))).not_to be_valid
      end

      it "requires exactly 16 characters" do
        expect(Trace.new(valid_attrs(trace_id: "abc"))).not_to be_valid
        expect(Trace.new(valid_attrs(trace_id: "a" * 17))).not_to be_valid
      end

      it "requires uniqueness" do
        Trace.create!(valid_attrs)
        duplicate = Trace.new(valid_attrs)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:trace_id]).to include("has already been taken")
      end
    end

    describe "agent_id" do
      it "requires presence" do
        expect(Trace.new(valid_attrs(agent_id: nil))).not_to be_valid
      end

      it "accepts any non-blank agent_id" do
        expect(Trace.new(valid_attrs(agent_id: "my-custom-agent"))).to be_valid
      end
    end

    describe "task_name" do
      it "requires presence" do
        expect(Trace.new(valid_attrs(task_name: nil))).not_to be_valid
      end
    end

    describe "start_time" do
      it "requires presence" do
        expect(Trace.new(valid_attrs(start_time: nil))).not_to be_valid
      end
    end
  end

  describe "status enum" do
    it "defaults to in_progress" do
      trace = Trace.create!(valid_attrs.except(:status))
      expect(trace).to be_in_progress
    end

    it "stores and retrieves all statuses" do
      %i[in_progress success error].each_with_index do |status, i|
        trace_id = format("%016x", 100 + i)
        trace = Trace.create!(valid_attrs(trace_id: trace_id, status: status))
        expect(trace.reload.status).to eq(status.to_s)
      end
    end

    it "raises ArgumentError for invalid status" do
      expect {
        Trace.new(valid_attrs(status: :unknown))
      }.to raise_error(ArgumentError)
    end

    it "provides predicate methods" do
      trace = Trace.new(valid_attrs(status: :success))
      expect(trace).to be_success
      expect(trace).not_to be_error
      expect(trace).not_to be_in_progress
    end

    it "provides named scopes" do
      Trace.create!(valid_attrs(trace_id: "a" * 16, status: :success))
      Trace.create!(valid_attrs(trace_id: "b" * 16, status: :error))
      Trace.create!(valid_attrs(trace_id: "c" * 16, status: :in_progress))

      expect(Trace.success.count).to eq(1)
      expect(Trace.error.count).to eq(1)
      expect(Trace.in_progress.count).to eq(1)
    end
  end

  describe "#duration" do
    let(:trace) { Trace.create!(valid_attrs) }

    def create_span(span_id, span_type, timestamp)
      Span.create!(
        trace_id:  trace.trace_id,
        span_id:   span_id,
        span_type: span_type,
        timestamp: timestamp,
        agent_id:  "support-agent",
        metadata:  { "task" => "classify_customer_ticket" }
      )
    end

    context "when the trace has no spans" do
      it "returns nil" do
        loaded = Trace.includes(:spans).find_by(trace_id: trace.trace_id)
        expect(loaded.duration).to be_nil
      end
    end

    context "when the trace has one span" do
      before { create_span("s1", "session_event", Time.utc(2026, 4, 2, 12, 0, 5)) }

      it "returns 0.0" do
        loaded = Trace.includes(:spans).find_by(trace_id: trace.trace_id)
        expect(loaded.duration).to eq(0.0)
      end
    end

    context "when the trace has multiple spans" do
      before do
        create_span("s1", "session_event", Time.utc(2026, 4, 2, 12, 0, 0))
        create_span("s2", "model_call",        Time.utc(2026, 4, 2, 12, 0, 2))
        create_span("s3", "span",     Time.utc(2026, 4, 2, 12, 0, 5))
      end

      it "returns elapsed seconds between earliest and latest span" do
        loaded = Trace.includes(:spans).find_by(trace_id: trace.trace_id)
        expect(loaded.duration).to eq(5.0)
      end
    end
  end
end
