class LogsController < ApplicationController
  SEVERITY_LEVELS = %w[DEBUG INFO WARN ERROR FATAL].freeze
  LOG_LIMIT = 500

  def index
    @severity  = params[:severity].presence&.upcase
    @severity  = nil unless SEVERITY_LEVELS.include?(@severity.to_s)
    @trace_id  = params[:trace_id].presence
    @subsystem = params[:subsystem].presence

    logs = Log.order(timestamp: :desc).limit(LOG_LIMIT)
    logs = logs.where(severity_text: @severity) if @severity
    logs = logs.where(trace_id: @trace_id)      if @trace_id
    logs = logs.to_a

    @subsystems = logs.filter_map { |l| l.log_attributes&.dig("openclaw.subsystem") }.uniq.sort
    logs = logs.select { |l| l.log_attributes&.dig("openclaw.subsystem") == @subsystem } if @subsystem
    @logs = logs
  end
end
