require "rails_helper"

# Phase 3: valid_payload and agent_id assertions updated to real fixture shape.
# Failures on agent_id and span_type assertions are intentional until Phase 4.

RSpec.describe "POST /v1/traces", type: :request do
  let(:headers) { { "Content-Type" => "text/plain" } }

  # ── Valid payload (real fixture) ─────────────────────────────────────────────

  describe "valid payload (model usage fixture)" do
    let(:valid_payload) { model_usage_fixture_json }

    it "returns 200 with {}" do
      post "/v1/traces", params: valid_payload, headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq({})
    end

    it "persists one trace and one span (flat single-span trace)" do
      expect {
        post "/v1/traces", params: valid_payload, headers: headers
      }.to change(Trace, :count).by(1).and change(Span, :count).by(1)
    end

    it "stores the correct trace_id (first 16 chars of OTLP traceId)" do
      post "/v1/traces", params: valid_payload, headers: headers
      expect(Trace.last.trace_id).to eq("3814946c5476f418")
    end

    it "stores agent_id from openclaw.sessionKey span attribute" do
      post "/v1/traces", params: valid_payload, headers: headers
      expect(Trace.last.agent_id).to eq("agent:main:discord:channel:1494326249361899544")
    end

    it "stores span_type model_call" do
      post "/v1/traces", params: valid_payload, headers: headers
      expect(Span.last.span_type).to eq("model_call")
    end
  end

  # ── Empty resourceSpans ───────────────────────────────────────────────────────

  describe "empty resourceSpans" do
    it "returns 200 with {} when resourceSpans is an empty array" do
      post "/v1/traces", params: JSON.generate("resourceSpans" => []), headers: headers
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
        post "/v1/traces", params: JSON.generate("resourceSpans" => []), headers: headers
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
      expect(JSON.parse(response.body)["error"]).to match(/invalid JSON/i)
    end
  end

  # ── No auth required ─────────────────────────────────────────────────────────

  describe "authentication" do
    it "accepts requests with no Authorization header" do
      post "/v1/traces", params: model_usage_fixture_json, headers: { "Content-Type" => "text/plain" }
      expect(response).to have_http_status(:ok)
    end

    it "accepts requests with an invalid Bearer token (auth is ignored)" do
      post "/v1/traces", params: model_usage_fixture_json,
           headers: { "Content-Type" => "text/plain", "Authorization" => "Bearer bogus" }
      expect(response).to have_http_status(:ok)
    end
  end

  # ── Protobuf payload ──────────────────────────────────────────────────────────

  describe "protobuf payload" do
    OTLP_PROTO_TRACE_ID = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"
    let(:pb_headers) { { "Content-Type" => "application/x-protobuf" } }

    def otlp_protobuf_payload
      trace_id_bytes = [OTLP_PROTO_TRACE_ID].pack("H*")
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
      av_str = ->(s) { pb_str.call(1, s) }
      kv_pair = ->(k, v_bytes) { pb_str.call(1, k) + pb_len.call(2, v_bytes) }

      span = pb_len.call(1, trace_id_bytes) +
             pb_len.call(2, span_id_bytes) +
             pb_str.call(5, "openclaw.model.usage") +
             pb_f64.call(7, 1_776_353_057_612_000_000) +
             pb_f64.call(8, 1_776_353_064_358_000_000)

      resource = pb_len.call(1, pb_len.call(1, kv_pair.call("service.name", av_str.call("openclaw-gateway"))))
      scope    = pb_len.call(2, pb_len.call(2, span))
      pb_len.call(1, resource + scope)
    end

    it "returns 200 with {} for a valid protobuf payload" do
      post "/v1/traces", params: otlp_protobuf_payload, headers: pb_headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq({})
    end

    it "persists a trace and span from a valid protobuf payload" do
      expect {
        post "/v1/traces", params: otlp_protobuf_payload, headers: pb_headers
      }.to change(Trace, :count).by(1).and change(Span, :count).by(1)
    end

    it "stores the correct trace_id" do
      post "/v1/traces", params: otlp_protobuf_payload, headers: pb_headers
      expect(Trace.last.trace_id).to eq(OTLP_PROTO_TRACE_ID.first(16))
    end

    it "returns 400 for malformed protobuf (truncated varint)" do
      post "/v1/traces", params: "\x8A".b, headers: pb_headers
      expect(response).to have_http_status(:bad_request)
    end

    it "returns an error key in the JSON body for malformed protobuf" do
      post "/v1/traces", params: "\x8A".b, headers: pb_headers
      expect(JSON.parse(response.body)).to have_key("error")
    end
  end

  # ── Multi-trace payload ───────────────────────────────────────────────────────

  describe "multi-trace payload" do
    MULTI_TRACE_ID_1 = "1111111111111111111111111111111111"
    MULTI_TRACE_ID_2 = "2222222222222222222222222222222222"

    def multi_trace_payload
      JSON.generate({
        "resourceSpans" => [{
          "resource" => {
            "attributes" => [
              { "key" => "service.name", "value" => { "stringValue" => "openclaw-gateway" } }
            ]
          },
          "scopeSpans" => [{ "spans" => [
            {
              "traceId"           => MULTI_TRACE_ID_1,
              "spanId"            => "span1111a",
              "name"              => "openclaw.model.usage",
              "startTimeUnixNano" => "1000000000000000000",
              "attributes"        => []
            },
            {
              "traceId"           => MULTI_TRACE_ID_2,
              "spanId"            => "span2222a",
              "name"              => "openclaw.message.processed",
              "startTimeUnixNano" => "2000000000000000000",
              "attributes"        => []
            }
          ]}]
        }]
      })
    end

    it "returns 200 with {}" do
      post "/v1/traces", params: multi_trace_payload, headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "persists one trace per distinct traceId" do
      expect {
        post "/v1/traces", params: multi_trace_payload, headers: headers
      }.to change(Trace, :count).by(2)
    end

    it "persists the correct trace_ids" do
      post "/v1/traces", params: multi_trace_payload, headers: headers
      stored = Trace.order(:trace_id).pluck(:trace_id).sort
      expected = [MULTI_TRACE_ID_1.first(16), MULTI_TRACE_ID_2.first(16)].sort
      expect(stored & expected).to eq(expected)
    end

    it "persists spans for each trace" do
      expect {
        post "/v1/traces", params: multi_trace_payload, headers: headers
      }.to change(Span, :count).by(2)
    end

    it "rolls back all traces when the second ingester call raises" do
      call_count = 0
      allow(TelemetryIngester).to receive(:call).and_wrap_original do |original, **kwargs|
        call_count += 1
        raise TelemetryIngester::Error, "injected failure" if call_count == 2
        original.call(**kwargs)
      end

      trace_count = Trace.count
      span_count  = Span.count

      post "/v1/traces", params: multi_trace_payload, headers: headers

      expect(Trace.count).to eq(trace_count)
      expect(Span.count).to eq(span_count)
      expect(response).to have_http_status(:bad_request)
    end
  end

  # ── Non-UTF-8 error message safety ────────────────────────────────────────────

  describe "non-UTF-8 error message safety" do
    let(:pb_headers) { { "Content-Type" => "application/x-protobuf" } }

    it "returns 400 (not 500) and parseable JSON when error message has non-UTF-8 bytes" do
      binary_message = "bad input: \xFF\xFE".b
      allow(OtlpProtobufDecoder).to receive(:decode_traces).and_raise(
        OtlpProtobufDecoder::Error, binary_message
      )

      post "/v1/traces", params: "\x00".b, headers: pb_headers

      expect(response).to have_http_status(:bad_request)
      expect { JSON.parse(response.body) }.not_to raise_error
      expect(JSON.parse(response.body)).to have_key("error")
    end
  end
end
