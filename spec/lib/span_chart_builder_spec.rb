# spec/lib/span_chart_builder_spec.rb
require "rails_helper"

RSpec.describe SpanChartBuilder do
  def fake_span(span_type:, span_name: nil, span_id: "abc123")
    instance_double(Span, span_type: span_type, span_name: span_name, span_id: span_id)
  end

  describe ".call with spans" do
    let(:spans) do
      [
        fake_span(span_type: "model_call", span_name: "agent.turn", span_id: "s1"),
        fake_span(span_type: "tool_call",  span_name: "Read",        span_id: "s2"),
        fake_span(span_type: "error",      span_name: nil,           span_id: "s3")
      ]
    end
    let(:latencies) { { "s1" => 2100.0, "s2" => 120.0, "s3" => 0.0 } }

    subject(:result) { described_class.call(spans: spans, latencies: latencies) }

    it "returns a horizontal bar chart" do
      expect(result[:options].dig(:chart, :type)).to eq("bar")
      expect(result[:options].dig(:plotOptions, :bar, :horizontal)).to be(true)
    end

    it "uses distributed mode for per-span coloring" do
      expect(result[:options].dig(:plotOptions, :bar, :distributed)).to be(true)
    end

    it "builds one data point per span with rounded duration" do
      data = result[:options].dig(:series, 0, :data)
      expect(data).to eq([
        { x: "agent.turn", y: 2100 },
        { x: "Read",       y: 120 },
        { x: "error",      y: 0 }
      ])
    end

    it "assigns CSS variable colors matching span types" do
      expect(result[:options][:colors]).to eq([
        "var(--color-span-model)",
        "var(--color-span-tool)",
        "var(--color-span-error)"
      ])
    end

    it "falls back to fg-muted for unknown span types" do
      spans  = [fake_span(span_type: "bogus", span_id: "sx")]
      result = described_class.call(spans: spans, latencies: { "sx" => 50.0 })
      expect(result[:options][:colors]).to eq(["var(--color-fg-muted)"])
    end

    it "uses span_type as label when span_name is nil" do
      data = result[:options].dig(:series, 0, :data)
      expect(data[2][:x]).to eq("error")
    end

    it "suppresses the legend" do
      expect(result[:options].dig(:legend, :show)).to be(false)
    end

    it "suppresses data labels" do
      expect(result[:options].dig(:dataLabels, :enabled)).to be(false)
    end
  end

  describe ".call with no spans" do
    subject(:result) { described_class.call(spans: [], latencies: {}) }

    it "returns a horizontal bar chart with empty series" do
      expect(result[:options].dig(:chart, :type)).to eq("bar")
      expect(result[:options][:series]).to eq([])
    end
  end
end
