require "rails_helper"

RSpec.describe ToolCallAnalyzer do
  def create_trace(overrides = {})
    Trace.create!({
      trace_id:   SecureRandom.hex(8),
      agent_id:   "support-agent",
      task_name:  "test_task",
      start_time: Time.zone.parse("2026-04-03T10:00:00Z"),
      status:     :success
    }.merge(overrides))
  end

  def create_span(trace, span_type:, metadata:, overrides: {})
    Span.create!({
      trace_id:       trace.trace_id,
      span_id:        SecureRandom.hex(4),
      parent_span_id: nil,
      span_type:      span_type,
      timestamp:      Time.zone.parse("2026-04-03T10:00:01Z"),
      agent_id:       trace.agent_id,
      metadata:       metadata
    }.merge(overrides))
  end

  def tool_result(trace, tool_name:, success:)
    create_span(trace,
      span_type: "tool_call",
      metadata:  { "tool_name" => tool_name, "success" => success, "result" => success ? "ok" : "error" }
    )
  end

  describe ".call" do
    it "returns an empty hash for an empty span collection" do
      expect(described_class.call([])).to eq({})
    end

    it "returns an empty hash when no tool_call spans are present" do
      trace = create_trace
      create_span(trace,
        span_type: "model_call",
        metadata:  { "model" => "claude-sonnet-4-6" }
      )

      expect(described_class.call(Span.all)).to eq({})
    end

    it "counts calls for a single tool" do
      trace = create_trace
      3.times { tool_result(trace, tool_name: "search", success: true) }

      result = described_class.call(Span.all)

      expect(result["search"][:calls]).to eq(3)
    end

    it "counts successes separately from total calls" do
      trace = create_trace
      tool_result(trace, tool_name: "fetch", success: true)
      tool_result(trace, tool_name: "fetch", success: true)
      tool_result(trace, tool_name: "fetch", success: false)

      result = described_class.call(Span.all)

      expect(result["fetch"][:successes]).to eq(2)
    end

    it "calculates success_rate as a Float between 0.0 and 1.0" do
      trace = create_trace
      2.times { tool_result(trace, tool_name: "lookup", success: true) }
      2.times { tool_result(trace, tool_name: "lookup", success: false) }

      result = described_class.call(Span.all)

      expect(result["lookup"][:success_rate]).to eq(0.5)
    end

    it "returns 0.0 success_rate when all calls fail" do
      trace = create_trace
      2.times { tool_result(trace, tool_name: "write", success: false) }

      result = described_class.call(Span.all)

      expect(result["write"][:success_rate]).to eq(0.0)
    end

    it "returns 1.0 success_rate when all calls succeed" do
      trace = create_trace
      3.times { tool_result(trace, tool_name: "classify", success: true) }

      result = described_class.call(Span.all)

      expect(result["classify"][:success_rate]).to eq(1.0)
    end

    it "groups multiple tools into separate hash keys" do
      trace = create_trace
      2.times { tool_result(trace, tool_name: "search",   success: true) }
      1.times { tool_result(trace, tool_name: "summarize", success: false) }

      result = described_class.call(Span.all)

      expect(result.keys).to contain_exactly("search", "summarize")
      expect(result["search"][:calls]).to eq(2)
      expect(result["summarize"][:calls]).to eq(1)
    end

    it "ignores spans of non-tool-call types" do
      trace = create_trace
      tool_result(trace, tool_name: "search", success: true)
      create_span(trace, span_type: "model_call",     metadata: { "model" => "claude-sonnet-4-6" })
      create_span(trace, span_type: "openclaw_event", metadata: { "reasoning" => "proceed" })

      result = described_class.call(Span.all)

      expect(result.keys).to eq(["search"])
    end

    it "accepts an ActiveRecord::Relation as input" do
      trace = create_trace
      tool_result(trace, tool_name: "fetch", success: true)

      result = described_class.call(Span.where(trace_id: trace.trace_id))

      expect(result["fetch"][:calls]).to eq(1)
    end
  end
end
