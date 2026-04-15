class DashboardController < ApplicationController
  def index
    @total_traces  = Trace.count
    @active_agents = Trace.distinct.count(:agent_id)
    recent_traces  = Trace.includes(:spans).where(start_time: 30.days.ago..)
    @error_rate_30d = ErrorRateAnalyzer.call(recent_traces).error_rate.round(1)
  end

  def error_rate_chart
    traces_by_day = Trace.includes(:spans)
                         .where(start_time: 30.days.ago..)
                         .order(:start_time)
                         .group_by { |t| t.start_time.to_date }

    series_data = traces_by_day.map do |date, day_traces|
      result = ErrorRateAnalyzer.call(day_traces)
      { x: date.to_time.to_i * 1000, y: result.error_rate.round(1) }
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
    traces_by_day = Trace.where(start_time: 30.days.ago..)
                         .order(:start_time)
                         .group_by { |t| t.start_time.to_date }

    series_data = traces_by_day.map do |date, day_traces|
      { x: date.to_time.to_i * 1000, y: day_traces.size }
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
end
