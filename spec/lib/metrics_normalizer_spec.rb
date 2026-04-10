require "rails_helper"

RSpec.describe MetricsNormalizer do
  # ── Fixture helpers ────────────────────────────────────────────────────────

  def otlp_metrics_payload(metrics:, resource_attrs: [])
    JSON.generate({
      "resourceMetrics" => [{
        "resource"    => { "attributes" => resource_attrs },
        "scopeMetrics" => [{ "metrics" => metrics }]
      }]
    })
  end

  def sum_metric(name:, data_points:)
    { "name" => name, "sum" => { "dataPoints" => data_points } }
  end

  def histogram_metric(name:, data_points:)
    { "name" => name, "histogram" => { "dataPoints" => data_points } }
  end

  def gauge_metric(name:, data_points:)
    { "name" => name, "gauge" => { "dataPoints" => data_points } }
  end

  def sum_point(value:, timestamp_ns:, start_ns: nil, attrs: [])
    pt = {
      "attributes"    => attrs,
      "timeUnixNano"  => timestamp_ns.to_s,
      "asInt"         => value
    }
    pt["startTimeUnixNano"] = start_ns.to_s if start_ns
    pt
  end

  def histogram_point(timestamp_ns:, attrs: [], **fields)
    {
      "attributes"     => attrs,
      "timeUnixNano"   => timestamp_ns.to_s
    }.merge(
      fields.transform_keys { |k|
        case k
        when :count           then "count"
        when :sum             then "sum"
        when :min             then "min"
        when :max             then "max"
        when :bucket_counts   then "bucketCounts"
        when :explicit_bounds then "explicitBounds"
        else k.to_s
        end
      }
    )
  end

  def string_attr(key, value)
    { "key" => key, "value" => { "stringValue" => value } }
  end

  BASE_TS = 1_712_345_678_500_000_000
  BASE_START_TS = 1_712_345_678_000_000_000

  # ── Sum metrics ────────────────────────────────────────────────────────────

  describe "sum metric" do
    let(:payload) do
      otlp_metrics_payload(metrics: [
        sum_metric(name: "gen_ai.client.token.usage", data_points: [
          sum_point(value: 1200, timestamp_ns: BASE_TS, start_ns: BASE_START_TS,
                    attrs: [string_attr("gen_ai.system", "anthropic")])
        ])
      ])
    end

    subject(:result) { MetricsNormalizer.call(payload) }

    it "returns one hash per data point" do
      expect(result.length).to eq(1)
    end

    it "sets metric_name" do
      expect(result[0]["metric_name"]).to eq("gen_ai.client.token.usage")
    end

    it "sets metric_type to sum" do
      expect(result[0]["metric_type"]).to eq("sum")
    end

    it "sets timestamp from timeUnixNano" do
      expected = Time.at(BASE_TS / 1_000_000_000.0).utc.iso8601(3)
      expect(result[0]["timestamp"]).to eq(expected)
    end

    it "sets data_points value from asInt" do
      expect(result[0]["data_points"]["value"]).to eq(1200)
    end

    it "sets data_points start_time from startTimeUnixNano" do
      expected = Time.at(BASE_START_TS / 1_000_000_000.0).utc.iso8601(3)
      expect(result[0]["data_points"]["start_time"]).to eq(expected)
    end

    it "flattens span attributes into metric_attributes" do
      expect(result[0]["metric_attributes"]).to eq("gen_ai.system" => "anthropic")
    end
  end

  describe "sum metric with asDouble value" do
    it "reads asDouble when asInt is absent" do
      payload = otlp_metrics_payload(metrics: [
        sum_metric(name: "latency", data_points: [
          { "attributes" => [], "timeUnixNano" => BASE_TS.to_s, "asDouble" => 3.14 }
        ])
      ])
      result = MetricsNormalizer.call(payload)
      expect(result[0]["data_points"]["value"]).to eq(3.14)
    end
  end

  # ── Histogram metrics ──────────────────────────────────────────────────────

  describe "histogram metric" do
    let(:payload) do
      otlp_metrics_payload(metrics: [
        histogram_metric(name: "gen_ai.client.operation.duration", data_points: [
          histogram_point(
            timestamp_ns:    BASE_TS,
            count:           150,
            sum:             45_230.0,
            min:             12.0,
            max:             890.0,
            bucket_counts:   [10, 40, 60, 30, 10],
            explicit_bounds: [100.0, 300.0, 500.0, 700.0]
          )
        ])
      ])
    end

    subject(:result) { MetricsNormalizer.call(payload) }

    it "sets metric_type to histogram" do
      expect(result[0]["metric_type"]).to eq("histogram")
    end

    it "sets count" do
      expect(result[0]["data_points"]["count"]).to eq(150)
    end

    it "sets sum" do
      expect(result[0]["data_points"]["sum"]).to eq(45_230.0)
    end

    it "sets min" do
      expect(result[0]["data_points"]["min"]).to eq(12.0)
    end

    it "sets max" do
      expect(result[0]["data_points"]["max"]).to eq(890.0)
    end

    it "sets bucket_counts (camelCase → snake_case)" do
      expect(result[0]["data_points"]["bucket_counts"]).to eq([10, 40, 60, 30, 10])
    end

    it "sets explicit_bounds (camelCase → snake_case)" do
      expect(result[0]["data_points"]["explicit_bounds"]).to eq([100.0, 300.0, 500.0, 700.0])
    end

    it "omits missing optional fields (min/max absent)" do
      payload = otlp_metrics_payload(metrics: [
        histogram_metric(name: "m", data_points: [
          histogram_point(timestamp_ns: BASE_TS, count: 5, sum: 100.0)
        ])
      ])
      result = MetricsNormalizer.call(payload)
      expect(result[0]["data_points"]).not_to have_key("min")
      expect(result[0]["data_points"]).not_to have_key("max")
    end
  end

  # ── Gauge metrics ──────────────────────────────────────────────────────────

  describe "gauge metric" do
    let(:payload) do
      otlp_metrics_payload(metrics: [
        gauge_metric(name: "cache.hit_ratio", data_points: [
          {
            "attributes"   => [string_attr("service.name", "openclaw")],
            "timeUnixNano" => BASE_TS.to_s,
            "asDouble"     => 0.87
          }
        ])
      ])
    end

    subject(:result) { MetricsNormalizer.call(payload) }

    it "returns one hash per data point" do
      expect(result.length).to eq(1)
    end

    it "sets metric_name" do
      expect(result[0]["metric_name"]).to eq("cache.hit_ratio")
    end

    it "sets metric_type to gauge" do
      expect(result[0]["metric_type"]).to eq("gauge")
    end

    it "sets timestamp from timeUnixNano" do
      expected = Time.at(BASE_TS / 1_000_000_000.0).utc.iso8601(3)
      expect(result[0]["timestamp"]).to eq(expected)
    end

    it "sets data_points value from asInt (scalar)" do
      payload = otlp_metrics_payload(metrics: [
        gauge_metric(name: "deploy.replicas.ready", data_points: [
          { "attributes" => [], "timeUnixNano" => BASE_TS.to_s, "asInt" => 3 }
        ])
      ])
      expect(MetricsNormalizer.call(payload)[0]["data_points"]["value"]).to eq(3)
    end

    it "sets data_points value from asDouble (scalar)" do
      expect(result[0]["data_points"]["value"]).to eq(0.87)
    end

    it "flattens data point attributes into metric_attributes" do
      expect(result[0]["metric_attributes"]).to eq("service.name" => "openclaw")
    end
  end

  # ── Multiple metrics ───────────────────────────────────────────────────────

  describe "multiple metrics and data points" do
    it "returns one hash per data point across all metrics" do
      payload = otlp_metrics_payload(metrics: [
        sum_metric(name: "tokens", data_points: [
          sum_point(value: 100, timestamp_ns: BASE_TS),
          sum_point(value: 200, timestamp_ns: BASE_TS + 1_000_000_000)
        ]),
        histogram_metric(name: "duration", data_points: [
          histogram_point(timestamp_ns: BASE_TS, count: 10, sum: 500.0)
        ])
      ])
      expect(MetricsNormalizer.call(payload).length).to eq(3)
    end
  end

  # ── trace_id ───────────────────────────────────────────────────────────────

  describe "trace_id" do
    it "reads trace_id from resource attributes" do
      payload = otlp_metrics_payload(
        metrics:       [sum_metric(name: "m", data_points: [sum_point(value: 1, timestamp_ns: BASE_TS)])],
        resource_attrs: [string_attr("trace_id", "a1b2c3d4e5f6a7b8")]
      )
      expect(MetricsNormalizer.call(payload)[0]["trace_id"]).to eq("a1b2c3d4e5f6a7b8")
    end

    it "sets trace_id to nil when absent" do
      payload = otlp_metrics_payload(
        metrics: [sum_metric(name: "m", data_points: [sum_point(value: 1, timestamp_ns: BASE_TS)])]
      )
      expect(MetricsNormalizer.call(payload)[0]["trace_id"]).to be_nil
    end
  end

  # ── Empty / missing input ──────────────────────────────────────────────────

  describe "empty and missing input" do
    it "returns [] for empty resourceMetrics array" do
      expect(MetricsNormalizer.call(JSON.generate("resourceMetrics" => []))).to eq([])
    end

    it "returns [] when resourceMetrics key is absent" do
      expect(MetricsNormalizer.call(JSON.generate({}))).to eq([])
    end

    it "returns [] when scopeMetrics is empty" do
      payload = JSON.generate("resourceMetrics" => [{ "resource" => { "attributes" => [] }, "scopeMetrics" => [] }])
      expect(MetricsNormalizer.call(payload)).to eq([])
    end

    it "skips metrics with no name" do
      payload = otlp_metrics_payload(metrics: [
        { "sum" => { "dataPoints" => [sum_point(value: 1, timestamp_ns: BASE_TS)] } }
      ])
      expect(MetricsNormalizer.call(payload)).to eq([])
    end

    it "skips metrics with unrecognised type (not sum, histogram, or gauge)" do
      payload = otlp_metrics_payload(metrics: [{ "name" => "m", "exponential_histogram" => {} }])
      expect(MetricsNormalizer.call(payload)).to eq([])
    end
  end

  # ── attrs_to_hash ──────────────────────────────────────────────────────────

  describe "attrs_to_hash (via metric_attributes)" do
    def payload_with_attrs(attrs)
      otlp_metrics_payload(metrics: [
        sum_metric(name: "m", data_points: [sum_point(value: 1, timestamp_ns: BASE_TS, attrs: attrs)])
      ])
    end

    it "extracts stringValue" do
      attrs = [{ "key" => "model", "value" => { "stringValue" => "claude-sonnet-4-6" } }]
      expect(MetricsNormalizer.call(payload_with_attrs(attrs))[0]["metric_attributes"]["model"])
        .to eq("claude-sonnet-4-6")
    end

    it "extracts intValue" do
      attrs = [{ "key" => "tokens", "value" => { "intValue" => 512 } }]
      expect(MetricsNormalizer.call(payload_with_attrs(attrs))[0]["metric_attributes"]["tokens"]).to eq(512)
    end

    it "extracts doubleValue" do
      attrs = [{ "key" => "cost", "value" => { "doubleValue" => 0.0042 } }]
      expect(MetricsNormalizer.call(payload_with_attrs(attrs))[0]["metric_attributes"]["cost"]).to eq(0.0042)
    end

    it "extracts boolValue: true" do
      attrs = [{ "key" => "cached", "value" => { "boolValue" => true } }]
      expect(MetricsNormalizer.call(payload_with_attrs(attrs))[0]["metric_attributes"]["cached"]).to eq(true)
    end

    it "extracts boolValue: false without losing the false value" do
      attrs = [{ "key" => "cached", "value" => { "boolValue" => false } }]
      expect(MetricsNormalizer.call(payload_with_attrs(attrs))[0]["metric_attributes"]["cached"]).to eq(false)
    end
  end

  # ── Error handling ─────────────────────────────────────────────────────────

  describe "error handling" do
    it "raises MetricsNormalizer::Error on invalid JSON" do
      expect { MetricsNormalizer.call("not json") }
        .to raise_error(MetricsNormalizer::Error, /invalid JSON/)
    end
  end
end
