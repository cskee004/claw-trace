class MetricsController < ApplicationController
  def index
    @chart_cards = build_chart_cards
  end

  def show
    @metric_name = params[:metric_name]
    records      = Metric.where(metric_name: @metric_name).order(:timestamp).to_a
    @metric_type = records.first&.metric_type
    @has_data    = records.any?
    @chart_options = @has_data ? MetricChartBuilder.call(records: records, metric_type: @metric_type) : {}
  end

  private

  def build_chart_cards
    build_metrics_summary.map do |m|
      records = Metric.where(metric_name: m.metric_name).order(:timestamp).to_a
      {
        metric_name: m.metric_name,
        metric_type: m.metric_type,
        options:     MetricChartBuilder.call(records: records, metric_type: m.metric_type)
      }
    end
  end

  def build_metrics_summary
    scope = Metric.all
    scope = scope.where("metric_name LIKE ?", "%#{params[:q]}%")                               if params[:q].present?
    scope = scope.where("json_extract(metric_attributes, '$.model') = ?",    params[:model])    if params[:model].present?
    scope = scope.where("json_extract(metric_attributes, '$.provider') = ?", params[:provider]) if params[:provider].present?
    scope = scope.where("json_extract(metric_attributes, '$.channel') = ?",  params[:channel])  if params[:channel].present?

    scope
      .select("metric_name, metric_type, MAX(timestamp) as latest_timestamp, COUNT(*) as data_point_count")
      .group(:metric_name, :metric_type)
      .order("latest_timestamp DESC")
  end
end
