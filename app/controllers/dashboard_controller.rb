class DashboardController < ApplicationController
  PERIODS = %w[12h 24h 7d 30d custom].freeze

  before_action :set_period

  def index
    @total_traces   = Trace.count
    @active_agents  = Trace.distinct.count(:agent_id)
    recent_traces   = Trace.includes(:spans).where(start_time: time_range)
    @error_rate_30d = ErrorRateAnalyzer.call(recent_traces).error_rate.round(1)
  end

  def error_rate_chart
    traces    = Trace.includes(:spans).where(start_time: time_range).order(:start_time)
    grouped   = group_by_period(traces)

    series_data = grouped.map do |key, bucket|
      { x: to_epoch_ms(key), y: ErrorRateAnalyzer.call(bucket).error_rate.round(1) }
    end

    @chart_options = {
      chart:  { type: "line", height: 240, toolbar: { show: false }, zoom: { enabled: false } },
      series: [{ name: "Error Rate %", data: series_data }],
      xaxis:  { type: "datetime" },
      yaxis:  { min: 0, max: 100, title: { text: "%" } },
      stroke: { curve: "smooth" },
      colors: ["var(--color-span-error)"]
    }
    render partial: "error_rate_chart"
  end

  def traces_volume_chart
    traces  = Trace.where(start_time: time_range).order(:start_time)
    grouped = group_by_period(traces)

    series_data = grouped.map do |key, bucket|
      { x: to_epoch_ms(key), y: bucket.size }
    end

    @chart_options = {
      chart:       { type: "bar", height: 240, toolbar: { show: false } },
      series:      [{ name: "Traces", data: series_data }],
      xaxis:       { type: "datetime" },
      yaxis:       { min: 0, title: { text: "Traces" } },
      colors:      ["var(--color-accent)"],
      plotOptions: { bar: { borderRadius: 2, columnWidth: "60%" } }
    }
    render partial: "traces_volume_chart"
  end

  private

  def set_period
    @current_period = PERIODS.include?(params[:period]) ? params[:period] : "30d"
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

  def group_by_period(traces)
    if @current_period.in?(%w[12h 24h])
      traces.group_by { |t| t.start_time.beginning_of_hour }
    else
      traces.group_by { |t| t.start_time.to_date }
    end
  end

  def to_epoch_ms(key)
    key.to_time.to_i * 1000
  end
end
