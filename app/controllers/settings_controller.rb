class SettingsController < ApplicationController
  RETENTION_DAYS_MIN = 1
  RETENTION_DAYS_MAX = 3650

  def show
    @retention_days = Setting.get("log_retention_days", default: "30")
  end

  def update
    days = params[:log_retention_days].to_s.strip
    unless days.match?(/\A\d+\z/) &&
           days.to_i.between?(RETENTION_DAYS_MIN, RETENTION_DAYS_MAX)
      flash.now[:alert] = "Retention must be a whole number between #{RETENTION_DAYS_MIN} and #{RETENTION_DAYS_MAX}."
      @retention_days = days
      return render :show, status: :unprocessable_entity
    end

    Setting.set("log_retention_days", days)
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
end
