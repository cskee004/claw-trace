require "rails_helper"

LOGS_ENDPOINT_BASE_TS = 1_712_345_678_500_000_000

RSpec.describe "POST /v1/logs", type: :request do
  let(:headers) { { "Content-Type" => "text/plain" } }

  def log_payload(log_records:)
    JSON.generate({
      "resourceLogs" => [{
        "resource"  => { "attributes" => [] },
        "scopeLogs" => [{ "logRecords" => log_records }]
      }]
    })
  end

  def log_record
    {
      "timeUnixNano"   => LOGS_ENDPOINT_BASE_TS.to_s,
      "severityText"   => "INFO",
      "severityNumber" => 9,
      "body"           => { "stringValue" => "agent turn completed" },
      "traceId"        => "a1b2c3d4e5f6a7b8",
      "spanId"         => "s1a2b3c4d5e6f7a8",
      "attributes"     => []
    }
  end

  # ── Valid payload ─────────────────────────────────────────────────────────────

  describe "valid payload" do
    let(:payload) { log_payload(log_records: [log_record]) }

    it "returns 200 with {}" do
      post "/v1/logs", params: payload, headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq({})
    end

    it "persists one Log record" do
      expect {
        post "/v1/logs", params: payload, headers: headers
      }.to change(Log, :count).by(1)
    end

    it "stores correct severity_text and body" do
      post "/v1/logs", params: payload, headers: headers
      log = Log.last
      expect(log.severity_text).to eq("INFO")
      expect(log.body).to eq("agent turn completed")
    end
  end

  # ── Empty resourceLogs ────────────────────────────────────────────────────────

  describe "empty resourceLogs" do
    it "returns 200 with {} when resourceLogs is an empty array" do
      post "/v1/logs",
           params:  JSON.generate("resourceLogs" => []),
           headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq({})
    end

    it "returns 200 with {} when resourceLogs key is absent" do
      post "/v1/logs", params: JSON.generate({}), headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq({})
    end

    it "persists nothing for empty resourceLogs" do
      expect {
        post "/v1/logs",
             params:  JSON.generate("resourceLogs" => []),
             headers: headers
      }.not_to change(Log, :count)
    end
  end

  # ── Malformed JSON ────────────────────────────────────────────────────────────

  describe "malformed JSON" do
    it "returns 400" do
      post "/v1/logs", params: "not json at all", headers: headers
      expect(response).to have_http_status(:bad_request)
    end

    it "returns an error message in the JSON body" do
      post "/v1/logs", params: "not json at all", headers: headers
      expect(JSON.parse(response.body)["error"]).to match(/invalid JSON/i)
    end
  end

  # ── No auth required ──────────────────────────────────────────────────────────

  describe "authentication" do
    let(:payload) { log_payload(log_records: [log_record]) }

    it "accepts requests with no Authorization header" do
      post "/v1/logs", params: payload, headers: { "Content-Type" => "text/plain" }
      expect(response).to have_http_status(:ok)
    end

    it "accepts requests with an invalid Bearer token (auth is ignored)" do
      post "/v1/logs", params: payload,
           headers: { "Content-Type" => "text/plain", "Authorization" => "Bearer bogus" }
      expect(response).to have_http_status(:ok)
    end
  end
end
