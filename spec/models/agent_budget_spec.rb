require "rails_helper"

RSpec.describe AgentBudget, type: :model do
  describe "validations" do
    it "is valid with agent_id and a positive daily_limit_usd" do
      expect(AgentBudget.new(agent_id: "bot-1", daily_limit_usd: 5.0)).to be_valid
    end

    it "requires agent_id" do
      expect(AgentBudget.new(agent_id: nil, daily_limit_usd: 5.0)).not_to be_valid
    end

    it "enforces uniqueness on agent_id" do
      AgentBudget.create!(agent_id: "bot-1", daily_limit_usd: 5.0)
      duplicate = AgentBudget.new(agent_id: "bot-1", daily_limit_usd: 10.0)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:agent_id]).to be_present
    end

    it "requires daily_limit_usd" do
      expect(AgentBudget.new(agent_id: "bot-1", daily_limit_usd: nil)).not_to be_valid
    end

    it "rejects daily_limit_usd of zero" do
      expect(AgentBudget.new(agent_id: "bot-1", daily_limit_usd: 0)).not_to be_valid
    end

    it "rejects negative daily_limit_usd" do
      expect(AgentBudget.new(agent_id: "bot-1", daily_limit_usd: -1.0)).not_to be_valid
    end
  end
end
