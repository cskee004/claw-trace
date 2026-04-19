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

  def create_span(trace, span_type:, metadata:, span_outcome: nil, overrides: {})
    Span.create!({
      trace_id:       trace.trace_id,
      span_id:        SecureRandom.hex(4),
      parent_span_id: nil,
      span_type:      span_type,
      span_outcome:   span_outcome,
      timestamp:      Time.zone.parse("2026-04-03T10:00:01Z"),
      agent_id:       trace.agent_id,
      metadata:       metadata
    }.merge(overrides))
  end

  # Builds a span matching what the openclaw-clawtrace plugin actually emits:
  # metadata key is "tool.name" (dot-separated), success determined by span_outcome.
  def tool_span(trace, tool_name:, outcome: "completed")
    create_span(trace,
      span_type:    "tool_call",
      span_outcome: outcome,
      metadata:     { "tool.name" => tool_name }
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
      3.times { tool_span(trace, tool_name: "search") }

      result = described_class.call(Span.all)

      expect(result["search"][:calls]).to eq(3)
    end

    it "counts successes separately from total calls" do
      trace = create_trace
      tool_span(trace, tool_name: "fetch", outcome: "completed")
      tool_span(trace, tool_name: "fetch", outcome: "completed")
      tool_span(trace, tool_name: "fetch", outcome: "error")

      result = described_class.call(Span.all)

      expect(result["fetch"][:successes]).to eq(2)
    end

    it "calculates success_rate as a Float between 0.0 and 1.0" do
      trace = create_trace
      2.times { tool_span(trace, tool_name: "lookup", outcome: "completed") }
      2.times { tool_span(trace, tool_name: "lookup", outcome: "error") }

      result = described_class.call(Span.all)

      expect(result["lookup"][:success_rate]).to eq(0.5)
    end

    it "returns 0.0 success_rate when all calls fail" do
      trace = create_trace
      2.times { tool_span(trace, tool_name: "write", outcome: "error") }

      result = described_class.call(Span.all)

      expect(result["write"][:success_rate]).to eq(0.0)
    end

    it "returns 1.0 success_rate when all calls succeed" do
      trace = create_trace
      3.times { tool_span(trace, tool_name: "classify", outcome: "completed") }

      result = described_class.call(Span.all)

      expect(result["classify"][:success_rate]).to eq(1.0)
    end

    it "groups multiple tools into separate hash keys" do
      trace = create_trace
      2.times { tool_span(trace, tool_name: "search",    outcome: "completed") }
      1.times { tool_span(trace, tool_name: "summarize", outcome: "error") }

      result = described_class.call(Span.all)

      expect(result.keys).to contain_exactly("search", "summarize")
      expect(result["search"][:calls]).to eq(2)
      expect(result["summarize"][:calls]).to eq(1)
    end

    it "ignores spans of non-tool-call types" do
      trace = create_trace
      tool_span(trace, tool_name: "search")
      create_span(trace, span_type: "model_call",     metadata: { "model" => "claude-sonnet-4-6" })
      create_span(trace, span_type: "openclaw_event", metadata: { "reasoning" => "proceed" })

      result = described_class.call(Span.all)

      expect(result.keys).to eq(["search"])
    end

    it "accepts an ActiveRecord::Relation as input" do
      trace = create_trace
      tool_span(trace, tool_name: "fetch")

      result = described_class.call(Span.where(trace_id: trace.trace_id))

      expect(result["fetch"][:calls]).to eq(1)
    end

    it "treats any non-error span_outcome as a success" do
      trace = create_trace
      tool_span(trace, tool_name: "run", outcome: "completed")
      tool_span(trace, tool_name: "run", outcome: "cancelled")
      tool_span(trace, tool_name: "run", outcome: "error")

      result = described_class.call(Span.all)

      expect(result["run"][:successes]).to eq(2)
    end

    it "reads tool name from the tool.name metadata key" do
      trace = create_trace
      create_span(trace,
        span_type:    "tool_call",
        span_outcome: "completed",
        metadata:     { "tool.name" => "bash_20250124" }
      )

      result = described_class.call(Span.all)

      expect(result.keys).to eq(["bash_20250124"])
    end
  end
end
