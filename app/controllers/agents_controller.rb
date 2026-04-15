class AgentsController < ApplicationController
  def index
    traces_by_agent = Trace.includes(:spans).all.group_by(&:agent_id)
    @agents = traces_by_agent.map do |agent_id, traces|
      AgentAggregator.call(agent_id: agent_id, traces: traces)
    end.sort_by { |a| a.last_seen || Time.zone.at(0) }.reverse
  end

  def show
    @agent_id  = params[:agent_id]
    all_traces = Trace.includes(:spans).where(agent_id: @agent_id).order(start_time: :desc)
    raise ActiveRecord::RecordNotFound, "No agent with id #{@agent_id}" if all_traces.empty?

    @aggregate = AgentAggregator.call(agent_id: @agent_id, traces: all_traces)
    @traces    = all_traces.first(20)
    @durations = TraceDurationCalculator.call_many(@traces)
  end
end
