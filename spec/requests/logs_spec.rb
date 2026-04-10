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

  # ── Protobuf payload ──────────────────────────────────────────────────────────

  describe "protobuf payload" do
    let(:pb_headers) { { "Content-Type" => "application/x-protobuf" } }

    # Hand-encoded minimal ExportLogsServiceRequest binary.
    # Replicates the pb_* helper lambdas from the decoder spec inline so the
    # request spec has no shared-helper dependency.
    def logs_protobuf_payload
      ts_ns          = 1_712_345_678_500_000_000
      trace_id_bytes = ["a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"].pack("H*")
      span_id_bytes  = ["aaaa0000aaaa0000"].pack("H*")

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

      pb_tag = ->(field, wire) { pb_varint.call((field << 3) | wire) }
      pb_len = ->(field, bytes) {
        bytes = bytes.b
        pb_tag.call(field, 2) + pb_varint.call(bytes.bytesize) + bytes
      }
      pb_str = ->(field, str) { pb_len.call(field, str.b) }
      pb_f64 = ->(field, val) { pb_tag.call(field, 1) + [val].pack("Q<") }
      pb_int = ->(field, int) { pb_tag.call(field, 0) + pb_varint.call(int) }
      av_str = ->(s) { pb_str.call(1, s) }

      log_record =
        pb_f64.call(1, ts_ns) +
        pb_int.call(2, 9) +
        pb_str.call(3, "INFO") +
        pb_len.call(5, av_str.call("agent turn completed")) +
        pb_len.call(9, trace_id_bytes) +
        pb_len.call(10, span_id_bytes)

      scope = pb_len.call(2, log_record)
      pb_len.call(1, pb_len.call(2, scope))
    end

    it "returns 200 with {} for a valid protobuf payload" do
      post "/v1/logs", params: logs_protobuf_payload, headers: pb_headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq({})
    end

    it "persists a Log record from a valid protobuf payload" do
      expect {
        post "/v1/logs", params: logs_protobuf_payload, headers: pb_headers
      }.to change(Log, :count).by(1)
    end

    it "returns 400 for malformed protobuf (truncated varint)" do
      post "/v1/logs", params: "\x8A".b, headers: pb_headers
      expect(response).to have_http_status(:bad_request)
    end

    it "returns an error key in the JSON body for malformed protobuf" do
      post "/v1/logs", params: "\x8A".b, headers: pb_headers
      expect(JSON.parse(response.body)).to have_key("error")
    end
  end
end
