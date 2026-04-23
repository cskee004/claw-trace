class AgentsController < ApplicationController
  include TimeWindowFilter

  def index
    traces_by_agent = Trace.includes(:spans).where(start_time: time_range).group_by(&:agent_id)
    @agents = traces_by_agent.map do |agent_id, traces|
      AgentAggregator.call(agent_id: agent_id, traces: traces)
    end.sort_by { |a| a.last_seen || Time.zone.at(0) }.reverse
  end

  def show
    @agent_id  = params[:agent_id]
    all_traces = Trace.includes(:spans).where(agent_id: @agent_id).order(start_time: :desc)
    raise ActiveRecord::RecordNotFound, "No agent with id #{@agent_id}" if all_traces.empty?

    @aggregate  = AgentAggregator.call(agent_id: @agent_id, traces: all_traces)
    @traces     = all_traces.first(20)
    @durations  = TraceDurationCalculator.call_many(@traces)
    @budget     = AgentBudget.find_by(agent_id: @agent_id)
    @cost_today = Span
      .where.not(span_model: nil)
      .where(agent_id: @agent_id)
      .where("timestamp >= ?", Time.current.beginning_of_day)
      .sum(:span_cost_usd)
      .to_f
  end

  def set_budget
    agent_id = params[:agent_id]
    budget = AgentBudget.find_or_initialize_by(agent_id: agent_id)
    budget.daily_limit_usd = params[:daily_limit_usd]
    if budget.save
      redirect_to agent_path(agent_id: agent_id)
    else
      redirect_to agent_path(agent_id: agent_id), alert: budget.errors.full_messages.join(", ")
    end
  end

  def delete_budget
    AgentBudget.find_by(agent_id: params[:agent_id])&.destroy
    redirect_to agent_path(agent_id: params[:agent_id])
  end

end
