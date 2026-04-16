require "rails_helper"

RSpec.describe AgentAggregator do
  def create_trace(agent_id:, status: :success, start_time: Time.zone.now)
    Trace.create!(
      trace_id:   SecureRandom.hex(8),
      agent_id:   agent_id,
      task_name:  "test_task",
      start_time: start_time,
      status:     status
    )
  end

  def create_span(trace, span_type: "span", timestamp: Time.zone.now, metadata: {}, span_outcome: nil)
    Span.create!(
      trace_id:       trace.trace_id,
      span_id:        SecureRandom.hex(4),
      parent_span_id: nil,
      span_type:      span_type,
      span_outcome:   span_outcome,
      timestamp:      timestamp,
      agent_id:       trace.agent_id,
      metadata:       metadata
    )
  end

  describe ".call" do
    let(:agent_id) { "agent-xyz" }

    context "with no traces" do
      subject(:result) { AgentAggregator.call(agent_id: agent_id, traces: []) }

      it "returns zero counts" do
        expect(result.total_runs).to eq(0)
        expect(result.success_count).to eq(0)
        expect(result.error_count).to eq(0)
      end

      it "returns 0.0 error_rate and empty top_tools" do
        expect(result.error_rate).to eq(0.0)
        expect(result.top_tools).to eq({})
      end

      it "returns nil avg_duration_ms and nil last_seen" do
        expect(result.avg_duration_ms).to be_nil
        expect(result.last_seen).to be_nil
      end

      it "returns the correct agent_id" do
        expect(result.agent_id).to eq(agent_id)
      end
    end

    context "with mixed traces" do
      let!(:t1) { create_trace(agent_id: agent_id, status: :success, start_time: 2.days.ago) }
      let!(:t2) { create_trace(agent_id: agent_id, status: :success, start_time: 1.day.ago) }
      let!(:t3) { create_trace(agent_id: agent_id, status: :error,   start_time: 1.hour.ago) }

      before do
        # t1: two tool_call spans 10 seconds apart → duration 10s
        create_span(t1, span_type: "tool_call",
                    timestamp: 2.days.ago,
                    metadata: { "tool_name" => "search", "success" => true })
        create_span(t1, span_type: "tool_call",
                    timestamp: 2.days.ago + 10.seconds,
                    metadata: { "tool_name" => "search", "success" => true })
        # t2: one tool_call span → duration 0
        create_span(t2, span_type: "tool_call",
                    timestamp: 1.day.ago,
                    metadata: { "tool_name" => "read_file", "success" => false })
        # t3: error-outcome span + terminal span 5 seconds later → duration 5s
        create_span(t3, span_outcome: "error", timestamp: 1.hour.ago)
        create_span(t3, timestamp: 1.hour.ago + 5.seconds)
      end

      let(:traces) { Trace.includes(:spans).where(agent_id: agent_id) }
      subject(:result) { AgentAggregator.call(agent_id: agent_id, traces: traces) }

      it "counts total_runs" do
        expect(result.total_runs).to eq(3)
      end

      it "counts success_count and error_count by Rails status enum" do
        expect(result.success_count).to eq(2)
        expect(result.error_count).to eq(1)
      end

      it "computes error_rate from ErrorRateAnalyzer (span-based: t3 has an error-outcome span)" do
        # 1 of 3 traces has an error-outcome span → 33.3%
        expect(result.error_rate).to be_within(0.1).of(33.3)
      end

      it "returns the most recent start_time as last_seen" do
        expect(result.last_seen.to_i).to be_within(5).of(1.hour.ago.to_i)
      end

      it "includes top_tools from all tool_call spans, sorted by call count" do
        expect(result.top_tools.keys.first).to eq("search")
        expect(result.top_tools["search"][:calls]).to eq(2)
      end

      it "limits top_tools to at most 5 entries even when more than 5 tools exist" do
        # Create spans for 6 distinct tools to exercise the .first(5) slice
        %w[tool_a tool_b tool_c tool_d tool_e tool_f].each do |name|
          create_span(t1, span_type: "tool_call",
                      timestamp: 2.days.ago + 1.second,
                      metadata: { "tool_name" => name, "success" => true })
        end
        fresh = Trace.includes(:spans).where(agent_id: agent_id)
        r = AgentAggregator.call(agent_id: agent_id, traces: fresh)
        expect(r.top_tools.size).to eq(5)
      end

      it "computes a non-nil avg_duration_ms when spans exist" do
        expect(result.avg_duration_ms).not_to be_nil
      end
    end
  end
end
