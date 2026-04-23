require "rails_helper"

RSpec.describe BudgetChecker do
  let(:agent_id) { "agent:main:discord:channel:123" }

  def create_trace(agent_id:)
    Trace.create!(
      trace_id:   SecureRandom.hex(8),
      agent_id:   agent_id,
      task_name:  "test",
      start_time: Time.current,
      status:     "success"
    )
  end

  def create_model_span(agent_id:, cost:, timestamp: Time.current)
    trace = create_trace(agent_id: agent_id)
    Span.create!(
      trace_id:       trace.trace_id,
      span_id:        SecureRandom.hex(4),
      span_type:      "agent_turn",
      span_name:      "openclaw.agent.turn",
      span_model:     "claude-haiku-4-5-20251001",
      timestamp:      timestamp,
      agent_id:       agent_id,
      metadata:       {},
      span_cost_usd:  cost
    )
  end

  describe ".check" do
    context "when no budgets are configured" do
      it "returns an empty array" do
        expect(BudgetChecker.check).to eq([])
      end
    end

    context "when agent is under budget" do
      before do
        AgentBudget.create!(agent_id: agent_id, daily_limit_usd: 5.00)
        create_model_span(agent_id: agent_id, cost: 0.87)
      end

      it "returns a result with over_budget false" do
        result = BudgetChecker.check.first
        expect(result.over_budget?).to be false
      end

      it "reports the correct spend" do
        result = BudgetChecker.check.first
        expect(result.spent_usd).to be_within(0.0001).of(0.87)
      end

      it "prints a summary line to stdout" do
        expect { BudgetChecker.check }.to output(/✓.*#{Regexp.escape(agent_id)}/).to_stdout
      end
    end

    context "when agent is over budget" do
      before do
        AgentBudget.create!(agent_id: agent_id, daily_limit_usd: 3.00)
        create_model_span(agent_id: agent_id, cost: 4.21)
      end

      it "returns a result with over_budget true" do
        result = BudgetChecker.check.first
        expect(result.over_budget?).to be true
      end

      it "reports the correct spend and excess" do
        result = BudgetChecker.check.first
        expect(result.spent_usd).to be_within(0.0001).of(4.21)
        expect(result.excess_usd).to be_within(0.0001).of(1.21)
      end

      it "prints a BUDGET ALERT to stdout" do
        expect { BudgetChecker.check }.to output(/BUDGET ALERT/).to_stdout
      end
    end

    context "when spans are from a previous day" do
      before do
        AgentBudget.create!(agent_id: agent_id, daily_limit_usd: 1.00)
        create_model_span(agent_id: agent_id, cost: 9.99, timestamp: 2.days.ago)
      end

      it "does not count yesterday's spend against today's budget" do
        result = BudgetChecker.check.first
        expect(result.spent_usd).to eq(0.0)
        expect(result.over_budget?).to be false
      end
    end
  end
end
