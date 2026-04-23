module TimeWindowFilter
  extend ActiveSupport::Concern

  PERIODS = %w[12h 24h 7d 30d custom].freeze

  included do
    before_action :set_period
  end

  private

  def default_period = "30d"

  def set_period
    @current_period = PERIODS.include?(params[:period]) ? params[:period] : default_period
    @period_label   = {
      "12h"    => "last 12 hours",
      "24h"    => "last 24 hours",
      "7d"     => "last 7 days",
      "30d"    => "last 30 days",
      "custom" => custom_period_label
    }[@current_period]
  end

  def custom_period_label
    from = params[:from].presence
    to   = params[:to].presence
    return "custom range" unless from && to
    "#{from} – #{to}"
  end

  def time_range
    case @current_period
    when "12h"   then 12.hours.ago..
    when "24h"   then 24.hours.ago..
    when "7d"    then 7.days.ago..
    when "custom"
      from = params[:from].presence&.then { |d| Time.zone.parse(d) rescue nil } || 30.days.ago
      to   = params[:to].presence&.then { |d| Time.zone.parse(d).end_of_day rescue nil } || Time.zone.now
      from..to
    else
      30.days.ago..
    end
  end
end
