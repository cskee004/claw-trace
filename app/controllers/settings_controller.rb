class SettingsController < ApplicationController
  RETENTION_DAYS_MIN = 1
  RETENTION_DAYS_MAX = 3650
  RETENTION_KEYS = %w[log_retention_days trace_retention_days metric_retention_days].freeze

  def show
    @log_retention_days    = Setting.get("log_retention_days",    default: "30")
    @trace_retention_days  = Setting.get("trace_retention_days",  default: "30")
    @metric_retention_days = Setting.get("metric_retention_days", default: "30")
  end

  def update
    key   = params[:setting_key].to_s
    value = params[:setting_value].to_s.strip
    unless RETENTION_KEYS.include?(key) &&
           value.match?(/\A\d+\z/) &&
           value.to_i.between?(RETENTION_DAYS_MIN, RETENTION_DAYS_MAX)
      flash[:alert] = "Invalid setting."
      return redirect_to settings_path
    end
    Setting.set(key, value)
    redirect_to settings_path, notice: "Settings saved."
  end

  def prune_logs
    retention_days = Setting.get("log_retention_days", default: "30").to_i
    result         = LogPruner.call(retention_days: retention_days)
    if result[:deleted] > 0
      flash[:notice] = "Pruned #{result[:deleted]} log records older than #{retention_days} days."
    else
      flash[:notice] = "No log records to prune."
    end
    redirect_to settings_path
  end

  def prune_traces
    retention_days = Setting.get("trace_retention_days", default: "30").to_i
    result         = TracePruner.call(retention_days: retention_days)
    if result[:deleted] > 0
      flash[:notice] = "Pruned #{result[:deleted]} trace records (and their spans) older than #{retention_days} days."
    else
      flash[:notice] = "No trace records to prune."
    end
    redirect_to settings_path
  end

  def delete_all_traces
    count = Trace.count
    Span.delete_all
    Trace.delete_all
    flash[:notice] = "Deleted all #{count} trace records and their spans."
    redirect_to settings_path
  end

  def prune_metrics
    retention_days = Setting.get("metric_retention_days", default: "30").to_i
    result         = MetricPruner.call(retention_days: retention_days)
    if result[:deleted] > 0
      flash[:notice] = "Pruned #{result[:deleted]} metric records older than #{retention_days} days."
    else
      flash[:notice] = "No metric records to prune."
    end
    redirect_to settings_path
  end

  def delete_all_metrics
    count = Metric.count
    Metric.delete_all
    flash[:notice] = "Deleted all #{count} metric records."
    redirect_to settings_path
  end

  def delete_all_logs
    count = Log.count
    Log.delete_all
    flash[:notice] = "Deleted all #{count} log records."
    redirect_to settings_path
  end
end
