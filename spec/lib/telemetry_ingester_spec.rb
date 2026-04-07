require "rails_helper"

RSpec.describe TelemetryIngester do
  def trace_data(overrides = {})
    {
      "trace_id"   => "a1b2c3d4e5f6a7b8",
      "agent_id"   => "support-agent",
      "task_name"  => "classify_customer_ticket",
      "start_time" => "2026-04-02T12:00:00Z",
      "status"     => "success"
    }.merge(overrides.transform_keys(&:to_s))
  end

  def span_data(overrides = {})
    {
      "trace_id"       => "a1b2c3d4e5f6a7b8",
      "span_id"        => "s1",
      "parent_span_id" => nil,
      "span_type"      => "agent_run_started",
      "timestamp"      => "2026-04-02T12:00:01Z",
      "agent_id"       => "support-agent",
      "metadata"       => { "task" => "classify_customer_ticket" }
    }.merge(overrides.transform_keys(&:to_s))
  end

  describe ".call" do
    it "persists the trace and returns trace_id and spans_ingested" do
      result = described_class.call(trace: trace_data, spans: [span_data])
      expect(result[:trace_id]).to eq("a1b2c3d4e5f6a7b8")
      expect(result[:spans_ingested]).to eq(1)
      expect(Trace.find_by(trace_id: "a1b2c3d4e5f6a7b8")).to be_present
      expect(Span.where(trace_id: "a1b2c3d4e5f6a7b8").count).to eq(1)
    end

    it "persists multiple spans" do
      spans = [
        span_data(span_id: "s1", span_type: "agent_run_started"),
        span_data(span_id: "s2", span_type: "model_call",
                  parent_span_id: "s1",
                  metadata: { "model_name" => "claude-sonnet-4-6", "prompt_tokens" => 100 })
      ]
      result = described_class.call(trace: trace_data, spans: spans)
      expect(result[:spans_ingested]).to eq(2)
    end

    it "accepts an empty spans array" do
      result = described_class.call(trace: trace_data, spans: [])
      expect(result[:spans_ingested]).to eq(0)
      expect(Trace.find_by(trace_id: "a1b2c3d4e5f6a7b8")).to be_present
    end

    it "raises Error when trace is nil" do
      expect { described_class.call(trace: nil, spans: []) }
        .to raise_error(TelemetryIngester::Error, /trace/)
    end

    it "raises Error when spans is not an array" do
      expect { described_class.call(trace: trace_data, spans: nil) }
        .to raise_error(TelemetryIngester::Error, /array/)
    end

    it "raises Error for an invalid span_type" do
      expect { described_class.call(trace: trace_data, spans: [span_data(span_type: "unknown_type")]) }
        .to raise_error(TelemetryIngester::Error)
    end

    it "rolls back the transaction if a span is invalid" do
      bad_span = span_data(span_type: "unknown_type")
      expect {
        described_class.call(trace: trace_data, spans: [span_data, bad_span]) rescue nil
      }.not_to change { Trace.count }
    end
  end
end
