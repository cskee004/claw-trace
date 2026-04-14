class SpansController < ApplicationController
  def logs
    span_id = params[:span_id]
    logs    = Log.where(span_id: span_id).order(:timestamp)
    render partial: "spans/logs", locals: { logs: logs, span_id: span_id }
  end
end
