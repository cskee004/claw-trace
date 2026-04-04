require "rails_helper"

RSpec.describe "POST /v1/traces", type: :request do
  let(:headers) { { "Content-Type" => "text/plain" } }

  OTLP_REQUEST_TRACE_ID = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"

  def otlp_payload(spans:, session_key: "support-agent")
    JSON.generate({
      "resourceSpans" => [{
        "resource" => {
          "attributes" => [
            { "key" => "openclaw.session.key", "value" => { "stringValue" => session_key } }
          ]
        },
        "scopeSpans" => [{ "spans" => spans }]
      }]
    })
  end

  def otlp_span(name:, span_id:, timestamp_ns:, parent_span_id: nil)
    span = {
      "traceId"           => OTLP_REQUEST_TRACE_ID,
      "spanId"            => span_id,
      "name"              => name,
      "startTimeUnixNano" => timestamp_ns.to_s
    }
    span["parentSpanId"] = parent_span_id if parent_span_id
    span
  end

  let(:valid_payload) do
    otlp_payload(spans: [
      otlp_span(name: "openclaw.request",    span_id: "aaaa0000aaaa0000", timestamp_ns: 1_000_000_000_000_000_000),
      otlp_span(name: "openclaw.agent.turn", span_id: "bbbb0000bbbb0000",
                parent_span_id: "aaaa0000aaaa0000",    timestamp_ns: 2_000_000_000_000_000_000)
    ])
  end

  # ── Valid payload ────────────────────────────────────────────────────────────

  describe "valid payload" do
    it "returns 200 with {}" do
      post "/v1/traces", params: valid_payload, headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq({})
    end

    it "persists one trace and two spans" do
      expect {
        post "/v1/traces", params: valid_payload, headers: headers
      }.to change(Trace, :count).by(1).and change(Span, :count).by(2)
    end

    it "stores the correct trace_id (first 16 chars of OTLP traceId)" do
      post "/v1/traces", params: valid_payload, headers: headers
      expect(Trace.last.trace_id).to eq(OTLP_REQUEST_TRACE_ID.first(16))
    end

    it "stores the correct agent_id from openclaw.session.key" do
      post "/v1/traces", params: valid_payload, headers: headers
      expect(Trace.last.agent_id).to eq("support-agent")
    end
  end

  # ── Empty resourceSpans ───────────────────────────────────────────────────────

  describe "empty resourceSpans" do
    it "returns 200 with {} when resourceSpans is an empty array" do
      post "/v1/traces",
           params:  JSON.generate("resourceSpans" => []),
           headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq({})
    end

    it "returns 200 with {} when resourceSpans key is absent" do
      post "/v1/traces", params: JSON.generate({}), headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq({})
    end

    it "persists nothing for empty resourceSpans" do
      expect {
        post "/v1/traces",
             params:  JSON.generate("resourceSpans" => []),
             headers: headers
      }.not_to change(Trace, :count)
    end
  end

  # ── Malformed JSON ────────────────────────────────────────────────────────────

  describe "malformed JSON" do
    it "returns 400" do
      post "/v1/traces", params: "not json at all", headers: headers
      expect(response).to have_http_status(:bad_request)
    end

    it "returns an error message" do
      post "/v1/traces", params: "not json at all", headers: headers
      body = JSON.parse(response.body)
      expect(body["error"]).to match(/invalid JSON/i)
    end
  end

  # ── No auth required ─────────────────────────────────────────────────────────

  describe "authentication" do
    it "accepts requests with no Authorization header" do
      post "/v1/traces", params: valid_payload, headers: { "Content-Type" => "text/plain" }
      expect(response).to have_http_status(:ok)
    end

    it "accepts requests with an invalid Bearer token (auth is ignored)" do
      post "/v1/traces", params: valid_payload,
           headers: { "Content-Type" => "text/plain", "Authorization" => "Bearer bogus" }
      expect(response).to have_http_status(:ok)
    end
  end
end
