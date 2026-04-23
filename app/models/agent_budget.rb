class AgentBudget < ApplicationRecord
  validates :agent_id,        presence: true, uniqueness: true
  validates :daily_limit_usd, presence: true, numericality: { greater_than: 0 }
end
