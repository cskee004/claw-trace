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
end
