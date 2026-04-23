class BudgetChecker
  Result = Struct.new(:agent_id, :spent_usd, :limit_usd, :over_budget, keyword_init: true) do
    def excess_usd    = spent_usd - limit_usd
    def excess_pct    = limit_usd.zero? ? 0 : ((excess_usd / limit_usd) * 100).round
    def over_budget?  = over_budget
  end

  def self.check
    new.check
  end

  def check
    budgets = AgentBudget.all.to_a
    return [] if budgets.empty?

    spends = Span
      .where.not(span_model: nil)
      .where(agent_id: budgets.map(&:agent_id))
      .where("timestamp >= ?", Time.current.beginning_of_day)
      .group(:agent_id)
      .sum(:span_cost_usd)
      .transform_values(&:to_f)

    budgets.map do |budget|
      spent  = spends.fetch(budget.agent_id, 0.0)
      result = Result.new(
        agent_id:    budget.agent_id,
        spent_usd:   spent,
        limit_usd:   budget.daily_limit_usd.to_f,
        over_budget: spent > budget.daily_limit_usd.to_f
      )
      print_result(result)
      result
    end
  end

  private

  def print_result(result)
    if result.over_budget?
      puts "⚠️  BUDGET ALERT: #{result.agent_id}"
      puts "   Spent: $#{"%.2f" % result.spent_usd} today (limit: $#{"%.2f" % result.limit_usd})"
      puts "   Excess: $#{"%.2f" % result.excess_usd} (#{result.excess_pct}% over)"
      puts
    else
      puts "✓  #{result.agent_id} — $#{"%.2f" % result.spent_usd} today (limit: $#{"%.2f" % result.limit_usd})"
    end
  end
end
