class SpansController < ApplicationController
  def logs
    span_id = params[:span_id]
    logs    = Log.where(span_id: span_id).order(:timestamp)
    # span_id passed separately so the partial can set the turbo-frame id even when logs is empty
    render partial: "spans/logs", locals: { logs: logs, span_id: span_id }
  end
end
