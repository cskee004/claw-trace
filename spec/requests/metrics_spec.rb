require "rails_helper"

METRICS_ENDPOINT_BASE_TS = 1_712_345_678_500_000_000

RSpec.describe "POST /v1/metrics", type: :request do
  let(:headers) { { "Content-Type" => "text/plain" } }

  def metrics_payload(metrics:, resource_attrs: [])
    JSON.generate({
      "resourceMetrics" => [{
        "resource"     => { "attributes" => resource_attrs },
        "scopeMetrics" => [{ "metrics" => metrics }]
      }]
    })
  end

  def sum_metric
    {
      "name" => "gen_ai.client.token.usage",
      "sum"  => {
        "dataPoints" => [{
          "attributes"        => [],
          "timeUnixNano"      => METRICS_ENDPOINT_BASE_TS.to_s,
          "startTimeUnixNano" => (METRICS_ENDPOINT_BASE_TS - 500_000_000).to_s,
          "asInt"             => 1200
        }]
      }
    }
  end

  # ── Valid payload ─────────────────────────────────────────────────────────────

  describe "valid payload" do
    let(:payload) { metrics_payload(metrics: [sum_metric]) }

    it "returns 200 with {}" do
      post "/v1/metrics", params: payload, headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq({})
    end

    it "persists one Metric record" do
      expect {
        post "/v1/metrics", params: payload, headers: headers
      }.to change(Metric, :count).by(1)
    end

    it "stores correct metric_name and metric_type" do
      post "/v1/metrics", params: payload, headers: headers
      m = Metric.last
      expect(m.metric_name).to eq("gen_ai.client.token.usage")
      expect(m.metric_type).to eq("sum")
    end
  end

  # ── Empty resourceMetrics ─────────────────────────────────────────────────────

  describe "empty resourceMetrics" do
    it "returns 200 with {} when resourceMetrics is an empty array" do
      post "/v1/metrics",
           params:  JSON.generate("resourceMetrics" => []),
           headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq({})
    end

    it "returns 200 with {} when resourceMetrics key is absent" do
      post "/v1/metrics", params: JSON.generate({}), headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq({})
    end

    it "persists nothing for empty resourceMetrics" do
      expect {
        post "/v1/metrics",
             params:  JSON.generate("resourceMetrics" => []),
             headers: headers
      }.not_to change(Metric, :count)
    end
  end

  # ── Malformed JSON ────────────────────────────────────────────────────────────

  describe "malformed JSON" do
    it "returns 400" do
      post "/v1/metrics", params: "not json at all", headers: headers
      expect(response).to have_http_status(:bad_request)
    end

    it "returns an error message" do
      post "/v1/metrics", params: "not json at all", headers: headers
      expect(JSON.parse(response.body)["error"]).to match(/invalid JSON/i)
    end
  end

  # ── No auth required ──────────────────────────────────────────────────────────

  describe "authentication" do
    let(:payload) { metrics_payload(metrics: [sum_metric]) }

    it "accepts requests with no Authorization header" do
      post "/v1/metrics", params: payload, headers: { "Content-Type" => "text/plain" }
      expect(response).to have_http_status(:ok)
    end

    it "accepts requests with an invalid Bearer token (auth is ignored)" do
      post "/v1/metrics", params: payload,
           headers: { "Content-Type" => "text/plain", "Authorization" => "Bearer bogus" }
      expect(response).to have_http_status(:ok)
    end
  end

  # ── Protobuf payload ──────────────────────────────────────────────────────────

  describe "protobuf payload" do
    let(:pb_headers) { { "Content-Type" => "application/x-protobuf" } }

    # Minimal valid ExportMetricsServiceRequest binary — one sum data point with asInt
    def metrics_protobuf_payload
      pb_varint = ->(int) {
        bytes = []
        loop do
          byte = int & 0x7F
          int >>= 7
          byte |= 0x80 if int > 0
          bytes << byte
          break if int.zero?
        end
        bytes.pack("C*")
      }

      pb_tag  = ->(field, wire) { pb_varint.call((field << 3) | wire) }
      pb_len  = ->(field, bytes) {
        bytes = bytes.b
        pb_tag.call(field, 2) + pb_varint.call(bytes.bytesize) + bytes
      }
      pb_str  = ->(field, str) { pb_len.call(field, str.b) }
      pb_f64  = ->(field, val) { pb_tag.call(field, 1) + [val].pack("Q<") }

      # NumberDataPoint with timeUnixNano (field 3) and asInt (field 6, sfixed64 wire_type 1)
      dp = pb_f64.call(3, METRICS_ENDPOINT_BASE_TS) +
           pb_tag.call(6, 1) + [1200].pack("q<")   # asInt as sfixed64

      sum    = pb_len.call(1, dp)                            # Sum.data_points = field 1
      metric = pb_str.call(1, "gen_ai.client.token.usage") + pb_len.call(7, sum)
      scope  = pb_len.call(3, metric)                        # ScopeMetrics.metrics = field 3
      pb_len.call(1, pb_len.call(2, scope))                  # ResourceMetrics.scope_metrics = field 2, ExportMetricsServiceRequest.resource_metrics = field 1
    end

    it "returns 200 with {} for a valid protobuf payload" do
      post "/v1/metrics", params: metrics_protobuf_payload, headers: pb_headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq({})
    end

    it "persists a Metric record from a valid protobuf payload" do
      expect {
        post "/v1/metrics", params: metrics_protobuf_payload, headers: pb_headers
      }.to change(Metric, :count).by(1)
    end

    it "returns 400 for malformed protobuf (truncated varint)" do
      post "/v1/metrics", params: "\x8A".b, headers: pb_headers
      expect(response).to have_http_status(:bad_request)
    end

    it "returns an error key in the JSON body for malformed protobuf" do
      post "/v1/metrics", params: "\x8A".b, headers: pb_headers
      expect(JSON.parse(response.body)).to have_key("error")
    end
  end
end
