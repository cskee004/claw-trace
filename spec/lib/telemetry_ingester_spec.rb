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
    # Stub broadcasts so rendering partials is never attempted in the test environment.
    # Individual broadcast tests override these stubs with expectations.
    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    end

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

    it "persists end_time when provided in span data" do
      span_with_end_time = span_data("end_time" => "2026-04-02T12:00:02.500Z")
      described_class.call(trace: trace_data, spans: [span_with_end_time])
      saved = Span.find_by(span_id: "s1")
      expect(saved.end_time).to be_present
      expect(saved.end_time.utc.iso8601(3)).to eq("2026-04-02T12:00:02.500Z")
    end

    it "persists end_time as nil when absent from span data" do
      described_class.call(trace: trace_data, spans: [span_data])
      saved = Span.find_by(span_id: "s1")
      expect(saved.end_time).to be_nil
    end

    it "persists span_name when provided in span data" do
      described_class.call(trace: trace_data, spans: [span_data("span_name" => "tool.web_search")])
      expect(Span.find_by(span_id: "s1").span_name).to eq("tool.web_search")
    end

    it "persists span_name as nil when absent from span data" do
      described_class.call(trace: trace_data, spans: [span_data])
      expect(Span.find_by(span_id: "s1").span_name).to be_nil
    end

    # ── Broadcast tests ──────────────────────────────────────────────────────────

    it "broadcasts a span append for each persisted span" do
      expect(Turbo::StreamsChannel).to receive(:broadcast_append_to)
        .with("trace:a1b2c3d4e5f6a7b8",
              hash_including(target: "waterfall-rows-a1b2c3d4e5f6a7b8",
                             partial: "traces/span_row"))
      described_class.call(trace: trace_data, spans: [span_data])
    end

    it "broadcasts one append per span when multiple spans are ingested" do
      spans = [
        span_data(span_id: "s1", span_type: "agent_run_started"),
        span_data(span_id: "s2", span_type: "model_call", parent_span_id: "s1")
      ]
      expect(Turbo::StreamsChannel).to receive(:broadcast_append_to)
        .with("trace:a1b2c3d4e5f6a7b8", hash_including(target: "waterfall-rows-a1b2c3d4e5f6a7b8"))
        .twice
      described_class.call(trace: trace_data, spans: spans)
    end

    it "broadcasts a summary replace after spans are appended" do
      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
        .with("trace:a1b2c3d4e5f6a7b8",
              hash_including(target: "trace-summary-a1b2c3d4e5f6a7b8",
                             partial: "traces/summary"))
      described_class.call(trace: trace_data, spans: [span_data])
    end

    it "does not broadcast when the transaction fails" do
      expect(Turbo::StreamsChannel).not_to receive(:broadcast_append_to)
      expect(Turbo::StreamsChannel).not_to receive(:broadcast_replace_to)
      described_class.call(
        trace: trace_data,
        spans: [span_data(span_type: "invalid_type")]
      ) rescue nil
    end

    it "does not broadcast when spans array is empty" do
      expect(Turbo::StreamsChannel).not_to receive(:broadcast_append_to)
      described_class.call(trace: trace_data, spans: [])
    end

    it "broadcasts span appends with correct locals keys" do
      expect(Turbo::StreamsChannel).to receive(:broadcast_append_to)
        .with(anything,
              hash_including(
                locals: hash_including(
                  span: an_instance_of(Span),
                  depth: 0,
                  total_ms: be_a(Float),
                  trace_start_time: be_a(Time)
                )
              ))
      described_class.call(trace: trace_data, spans: [span_data])
    end
  end
end
