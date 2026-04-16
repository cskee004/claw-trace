# app/lib/span_chart_builder.rb
#
# Builds an ApexCharts horizontal bar chart from a collection of Span records
# and their precomputed latencies. Each span becomes one bar, colored by span_type.
#
# Usage:
#   SpanChartBuilder.call(spans: ordered_spans, latencies: latency_hash)
#
# Returns { options: <ApexCharts hash> }
class SpanChartBuilder
  SPAN_TYPE_COLOR = {
    "model_call"      => "var(--color-span-model)",
    "message_event"   => "var(--color-span-message)",
    "tool_call"       => "var(--color-span-tool)",
    "session_event"   => "var(--color-span-lifecycle)",
    "command_event"   => "var(--color-span-lifecycle)",
    "webhook_event"   => "var(--color-span-lifecycle)",
    "openclaw_event"  => "var(--color-span-openclaw)",
    "span"            => "var(--color-fg-muted)"
  }.freeze

  FALLBACK_COLOR = "var(--color-fg-muted)".freeze

  FALLBACK_OPTIONS = {
    chart:       { type: "bar", height: 180, toolbar: { show: false } },
    series:      [],
    plotOptions: { bar: { horizontal: true } }
  }.freeze

  def self.call(spans:, latencies:)
    new(spans: spans, latencies: latencies).call
  end

  def initialize(spans:, latencies:)
    @spans     = spans
    @latencies = latencies
  end

  def call
    return { options: FALLBACK_OPTIONS.dup } if @spans.empty?
    { options: build_options }
  end

  private

  def build_options
    data   = @spans.map { |s| { x: label_for(s), y: (@latencies[s.span_id] || 0).round } }
    colors = @spans.map { |s| SPAN_TYPE_COLOR.fetch(s.span_type, FALLBACK_COLOR) }

    {
      chart:       { type: "bar", height: chart_height, toolbar: { show: false } },
      series:      [{ name: "Duration (ms)", data: data }],
      plotOptions: { bar: { horizontal: true, distributed: true, barHeight: "70%" } },
      colors:      colors,
      xaxis:       { title: { text: "Duration (ms)" } },
      yaxis:       { labels: { maxWidth: 220 } },
      legend:      { show: false },
      dataLabels:  { enabled: false }
    }
  end

  def label_for(span)
    span.span_name.presence || span.span_type
  end

  def chart_height
    ((@spans.size * 28) + 60).clamp(180, 600)
  end
end
