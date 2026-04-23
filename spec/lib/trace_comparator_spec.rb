require "rails_helper"

RSpec.describe TraceComparator do
  def make_trace(agent_id: "agent-1")
    Trace.create!(
      trace_id:   SecureRandom.hex(8),
      agent_id:   agent_id,
      task_name:  "test",
      start_time: Time.zone.now,
      status:     :success
    )
  end

  def make_span(trace, overrides = {})
    Span.create!({
      trace_id:       trace.trace_id,
      span_id:        SecureRandom.hex(4),
      parent_span_id: nil,
      span_type:      "model_call",
      span_name:      "openclaw.model.call",
      timestamp:      Time.zone.parse("2026-04-03T10:00:00Z"),
      agent_id:       trace.agent_id,
      metadata:       {}
    }.merge(overrides))
  end

  describe ".call" do
    context "cost stats" do
      it "sums span_cost_usd across all spans" do
        trace_a = make_trace
        make_span(trace_a, span_cost_usd: 0.001234)
        make_span(trace_a, span_cost_usd: 0.000500)

        trace_b = make_trace
        make_span(trace_b, span_cost_usd: nil)

        result = described_class.call(trace_a.reload, trace_b.reload)

        expect(result.stats[:cost_usd_a]).to eq(0.001734)
        expect(result.stats[:cost_usd_b]).to eq(0.0)
      end
    end

    context "token stats" do
      it "sums input and output tokens across all spans" do
        trace_a = make_trace
        make_span(trace_a, span_input_tokens: 100, span_output_tokens: 50)
        make_span(trace_a, span_input_tokens: 200, span_output_tokens: 80, span_type: "agent_turn")

        trace_b = make_trace
        make_span(trace_b, span_input_tokens: 300, span_output_tokens: 10)

        result = described_class.call(trace_a.reload, trace_b.reload)

        expect(result.stats[:input_tokens_a]).to eq(300)
        expect(result.stats[:output_tokens_a]).to eq(130)
        expect(result.stats[:input_tokens_b]).to eq(300)
        expect(result.stats[:output_tokens_b]).to eq(10)
      end

      it "treats nil token fields as 0" do
        trace_a = make_trace
        make_span(trace_a, span_input_tokens: nil, span_output_tokens: nil)
        trace_b = make_trace

        result = described_class.call(trace_a.reload, trace_b.reload)

        expect(result.stats[:input_tokens_a]).to eq(0)
        expect(result.stats[:output_tokens_a]).to eq(0)
      end
    end

    context "duration stats" do
      it "returns duration_ms from TraceDurationCalculator" do
        trace_a = make_trace
        make_span(trace_a, timestamp: Time.zone.parse("2026-04-03T10:00:00Z"))
        make_span(trace_a, timestamp: Time.zone.parse("2026-04-03T10:00:02Z"), span_type: "span")

        trace_b = make_trace
        make_span(trace_b, timestamp: Time.zone.parse("2026-04-03T10:00:00Z"))
        make_span(trace_b, timestamp: Time.zone.parse("2026-04-03T10:00:05Z"), span_type: "span")

        result = described_class.call(trace_a.reload, trace_b.reload)

        expect(result.stats[:duration_ms_a]).to eq(2000.0)
        expect(result.stats[:duration_ms_b]).to eq(5000.0)
      end

      it "returns nil duration when a trace has no spans" do
        trace_a = make_trace
        trace_b = make_trace
        make_span(trace_b)

        result = described_class.call(trace_a.reload, trace_b.reload)

        expect(result.stats[:duration_ms_a]).to be_nil
      end
    end

    context "error counts" do
      it "counts spans with span_outcome == 'error'" do
        trace_a = make_trace
        make_span(trace_a, span_outcome: "error")
        make_span(trace_a, span_outcome: "error", span_type: "agent_turn")
        make_span(trace_a, span_outcome: "completed")

        trace_b = make_trace
        make_span(trace_b, span_outcome: "completed")

        result = described_class.call(trace_a.reload, trace_b.reload)

        expect(result.stats[:error_count_a]).to eq(2)
        expect(result.stats[:error_count_b]).to eq(0)
      end
    end

    context "span counts by type" do
      it "returns a hash of span_type => count for each trace" do
        trace_a = make_trace
        make_span(trace_a, span_type: "model_call")
        make_span(trace_a, span_type: "model_call")
        make_span(trace_a, span_type: "tool_call")

        trace_b = make_trace
        make_span(trace_b, span_type: "agent_turn")

        result = described_class.call(trace_a.reload, trace_b.reload)

        expect(result.stats[:span_counts_a]).to eq("model_call" => 2, "tool_call" => 1)
        expect(result.stats[:span_counts_b]).to eq("agent_turn" => 1)
      end
    end

    context "name set membership" do
      it "builds names_a and names_b from span_name fields" do
        trace_a = make_trace
        make_span(trace_a, span_name: "openclaw.model.call")
        make_span(trace_a, span_name: "openclaw.tool.exec", span_type: "tool_call")

        trace_b = make_trace
        make_span(trace_b, span_name: "openclaw.model.call")
        make_span(trace_b, span_name: "openclaw.agent.turn", span_type: "agent_turn")

        result = described_class.call(trace_a.reload, trace_b.reload)

        expect(result.names_a).to include("openclaw.model.call", "openclaw.tool.exec")
        expect(result.names_b).to include("openclaw.model.call", "openclaw.agent.turn")
        expect(result.names_a).not_to include("openclaw.agent.turn")
        expect(result.names_b).not_to include("openclaw.tool.exec")
      end

      it "excludes nil span_names from sets" do
        trace_a = make_trace
        make_span(trace_a, span_name: nil)
        trace_b = make_trace

        result = described_class.call(trace_a.reload, trace_b.reload)

        expect(result.names_a).to be_empty
      end
    end
  end
end
