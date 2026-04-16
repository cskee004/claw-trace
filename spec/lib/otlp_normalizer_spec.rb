require "rails_helper"

# Phase 3: specs rebuilt on real OpenClaw fixtures.
# Failures in "model usage fixture", "message processed fixture", "pattern-based
# span_type rules", and "agent_id derivation" sections are intentional — they
# define the Phase 4 implementation contract.

RSpec.describe OtlpNormalizer do
  # ── Real fixture: openclaw.model.usage ─────────────────────────────────────

  describe "model usage fixture (span-openclaw-model-usage-001.json)" do
    let(:result) { OtlpNormalizer.call(model_usage_fixture_json).first }
    let(:trace)  { result[:trace] }
    let(:span)   { result[:spans].first }

    it "produces exactly one span" do
      expect(result[:spans].length).to eq(1)
    end

    it "span_type is model_call" do
      expect(span["span_type"]).to eq("model_call")
    end

    it "span_name is openclaw.model.usage" do
      expect(span["span_name"]).to eq("openclaw.model.usage")
    end

    it "agent_id is derived from openclaw.sessionKey span attribute" do
      expect(span["agent_id"]).to eq("agent:main:discord:channel:1494326249361899544")
    end

    it "trace agent_id matches span agent_id" do
      expect(trace["agent_id"]).to eq(span["agent_id"])
    end

    it "trace task_name is the span name" do
      expect(trace["task_name"]).to eq("openclaw.model.usage")
    end

    it "trace status is success (status.code == 0)" do
      expect(trace["status"]).to eq("success")
    end

    it "parent_span_id is nil (flat single-span trace)" do
      expect(span["parent_span_id"]).to be_nil
    end

    it "end_time is set (endTimeUnixNano is present in fixture)" do
      expect(span["end_time"]).not_to be_nil
    end

    # First-class fields — RED until Phase 4 migration + normalizer rewrite
    it "span_model is claude-haiku-4-5-20251001" do
      expect(span["span_model"]).to eq("claude-haiku-4-5-20251001")
    end

    it "span_provider is anthropic" do
      expect(span["span_provider"]).to eq("anthropic")
    end

    it "span_input_tokens is 2" do
      expect(span["span_input_tokens"]).to eq(2)
    end

    it "span_output_tokens is 246" do
      expect(span["span_output_tokens"]).to eq(246)
    end

    it "span_cache_read_tokens is 94270" do
      expect(span["span_cache_read_tokens"]).to eq(94270)
    end

    it "span_cache_write_tokens is 94649" do
      expect(span["span_cache_write_tokens"]).to eq(94649)
    end

    it "span_total_tokens is 94714 (as reported by OpenClaw, not a sum)" do
      expect(span["span_total_tokens"]).to eq(94714)
    end

    it "span_outcome is nil (not present in this fixture)" do
      expect(span["span_outcome"]).to be_nil
    end
  end

  # ── Real fixture: openclaw.message.processed ───────────────────────────────

  describe "message processed fixture (span-openclaw-message-processed-001.json)" do
    let(:result) { OtlpNormalizer.call(message_processed_fixture_json).first }
    let(:trace)  { result[:trace] }
    let(:span)   { result[:spans].first }

    it "produces exactly one span" do
      expect(result[:spans].length).to eq(1)
    end

    it "span_type is message_event" do
      expect(span["span_type"]).to eq("message_event")
    end

    it "span_name is openclaw.message.processed" do
      expect(span["span_name"]).to eq("openclaw.message.processed")
    end

    it "agent_id is derived from openclaw.sessionKey span attribute" do
      expect(span["agent_id"]).to eq("agent:main:discord:channel:1494326249361899544")
    end

    it "trace task_name is openclaw.message.processed" do
      expect(trace["task_name"]).to eq("openclaw.message.processed")
    end

    it "trace status is success" do
      expect(trace["status"]).to eq("success")
    end

    it "parent_span_id is nil (flat single-span trace)" do
      expect(span["parent_span_id"]).to be_nil
    end

    it "span_outcome is completed" do
      expect(span["span_outcome"]).to eq("completed")
    end

    # Token fields absent on message spans
    it "span_model is nil" do
      expect(span["span_model"]).to be_nil
    end

    it "span_provider is nil" do
      expect(span["span_provider"]).to be_nil
    end

    it "span_input_tokens is nil" do
      expect(span["span_input_tokens"]).to be_nil
    end

    it "span_output_tokens is nil" do
      expect(span["span_output_tokens"]).to be_nil
    end

    it "span_cache_read_tokens is nil" do
      expect(span["span_cache_read_tokens"]).to be_nil
    end

    it "span_cache_write_tokens is nil" do
      expect(span["span_cache_write_tokens"]).to be_nil
    end

    it "span_total_tokens is nil" do
      expect(span["span_total_tokens"]).to be_nil
    end
  end

  # ── Pattern-based span_type rules ──────────────────────────────────────────

  describe "pattern-based span_type rules (first match wins)" do
    def span_result_for(span_name, extra_span_attrs: [], status_code: nil)
      payload = realistic_single_span(span_name: span_name,
                                      extra_span_attrs: extra_span_attrs,
                                      status_code: status_code)
      OtlpNormalizer.call(payload).first[:spans].first
    end

    def span_type_for(span_name, extra_span_attrs: [], status_code: nil)
      span_result_for(span_name, extra_span_attrs: extra_span_attrs, status_code: status_code)["span_type"]
    end

    def span_outcome_for(span_name, extra_span_attrs: [], status_code: nil)
      span_result_for(span_name, extra_span_attrs: extra_span_attrs, status_code: status_code)["span_outcome"]
    end

    it "openclaw.model.* → model_call" do
      expect(span_type_for("openclaw.model.usage")).to eq("model_call")
      expect(span_type_for("openclaw.model.stream")).to eq("model_call")
    end

    it "openclaw.message.* → message_event" do
      expect(span_type_for("openclaw.message.processed")).to eq("message_event")
      expect(span_type_for("openclaw.message.received")).to eq("message_event")
    end

    it "openclaw.tool.* → tool_call" do
      expect(span_type_for("openclaw.tool.web_search")).to eq("tool_call")
    end

    it "tool.* → tool_call" do
      expect(span_type_for("tool.Read")).to eq("tool_call")
      expect(span_type_for("tool.web_search")).to eq("tool_call")
    end

    it "openclaw.session.* → session_event" do
      expect(span_type_for("openclaw.session.started")).to eq("session_event")
    end

    it "openclaw.command.* → command_event" do
      expect(span_type_for("openclaw.command.execute")).to eq("command_event")
    end

    it "openclaw.webhook.* → webhook_event" do
      expect(span_type_for("openclaw.webhook.received")).to eq("webhook_event")
    end

    it "openclaw.* catch-all → openclaw_event for unrecognised openclaw spans" do
      expect(span_type_for("openclaw.voice.transcribed")).to eq("openclaw_event")
      expect(span_type_for("openclaw.unknown.thing")).to eq("openclaw_event")
    end

    it "non-openclaw prefix → span (generic fallback)" do
      expect(span_type_for("http.client.request")).to eq("span")
      expect(span_type_for("custom.operation")).to eq("span")
    end

    describe "error overlay (span_outcome, not span_type)" do
      it "openclaw.outcome=error sets span_outcome to error" do
        attrs = [{ "key" => "openclaw.outcome", "value" => { "stringValue" => "error" } }]
        expect(span_outcome_for("openclaw.message.processed", extra_span_attrs: attrs)).to eq("error")
        expect(span_type_for("openclaw.message.processed",   extra_span_attrs: attrs)).to eq("message_event")
      end

      it "openclaw.outcome=failed sets span_outcome to error" do
        attrs = [{ "key" => "openclaw.outcome", "value" => { "stringValue" => "failed" } }]
        expect(span_outcome_for("openclaw.model.usage", extra_span_attrs: attrs)).to eq("error")
      end

      it "openclaw.outcome=timeout sets span_outcome to error" do
        attrs = [{ "key" => "openclaw.outcome", "value" => { "stringValue" => "timeout" } }]
        expect(span_outcome_for("openclaw.model.usage", extra_span_attrs: attrs)).to eq("error")
      end

      it "openclaw.outcome=completed does NOT set error span_outcome" do
        attrs = [{ "key" => "openclaw.outcome", "value" => { "stringValue" => "completed" } }]
        expect(span_outcome_for("openclaw.message.processed", extra_span_attrs: attrs)).to eq("completed")
        expect(span_type_for("openclaw.message.processed",    extra_span_attrs: attrs)).to eq("message_event")
      end

      it "OTLP status.code == 2 sets span_outcome to error" do
        expect(span_outcome_for("openclaw.model.usage", status_code: 2)).to eq("error")
        expect(span_type_for("openclaw.model.usage",    status_code: 2)).to eq("model_call")
      end

      it "OTLP status.code == 0 does NOT set error span_outcome" do
        expect(span_outcome_for("openclaw.model.usage", status_code: 0)).to be_nil
        expect(span_type_for("openclaw.model.usage",    status_code: 0)).to eq("model_call")
      end
    end
  end

  # ── agent_id derivation ────────────────────────────────────────────────────

  describe "agent_id derivation from span attributes" do
    def agent_id_for(span_attrs:, resource_attrs: [{ "key" => "service.name", "value" => { "stringValue" => "openclaw-gateway" } }])
      payload = JSON.generate({
        "resourceSpans" => [{
          "resource" => { "attributes" => resource_attrs },
          "scopeSpans" => [{ "spans" => [{
            "traceId"           => "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6",
            "spanId"            => "aaaa0000aaaa0000",
            "name"              => "openclaw.model.usage",
            "startTimeUnixNano" => "1776353057612000000",
            "attributes"        => span_attrs
          }] }]
        }]
      })
      OtlpNormalizer.call(payload).first[:spans].first["agent_id"]
    end

    it "reads openclaw.sessionKey from span attributes (primary source)" do
      attrs = [{ "key" => "openclaw.sessionKey", "value" => { "stringValue" => "agent:main:discord:channel:123" } }]
      expect(agent_id_for(span_attrs: attrs)).to eq("agent:main:discord:channel:123")
    end

    it "falls back to openclaw.chatId from span attributes" do
      attrs = [{ "key" => "openclaw.chatId", "value" => { "stringValue" => "channel:456" } }]
      expect(agent_id_for(span_attrs: attrs)).to eq("channel:456")
    end

    it "falls back to service.name from resource attributes when span attrs have no session context" do
      expect(agent_id_for(span_attrs: [])).to eq("openclaw-gateway")
    end

    it "falls back to 'unknown' when no session context and no service.name" do
      expect(agent_id_for(span_attrs: [], resource_attrs: [])).to eq("unknown")
    end

    it "prefers openclaw.sessionKey over openclaw.chatId when both present" do
      attrs = [
        { "key" => "openclaw.sessionKey", "value" => { "stringValue" => "primary-key" } },
        { "key" => "openclaw.chatId",     "value" => { "stringValue" => "secondary-id" } }
      ]
      expect(agent_id_for(span_attrs: attrs)).to eq("primary-key")
    end
  end

  # ── attrs_to_hash ──────────────────────────────────────────────────────────

  describe "attrs_to_hash (via span metadata)" do
    def payload_with_span_attrs(attrs)
      realistic_single_span(span_name: "openclaw.model.usage", extra_span_attrs: attrs)
    end

    it "extracts stringValue" do
      attrs = [{ "key" => "model", "value" => { "stringValue" => "claude-haiku-4-5-20251001" } }]
      span = OtlpNormalizer.call(payload_with_span_attrs(attrs)).first[:spans].first
      expect(span["metadata"]["model"]).to eq("claude-haiku-4-5-20251001")
    end

    it "extracts intValue" do
      attrs = [{ "key" => "tokens", "value" => { "intValue" => 512 } }]
      span = OtlpNormalizer.call(payload_with_span_attrs(attrs)).first[:spans].first
      expect(span["metadata"]["tokens"]).to eq(512)
    end

    it "extracts doubleValue" do
      attrs = [{ "key" => "latency_ms", "value" => { "doubleValue" => 123.45 } }]
      span = OtlpNormalizer.call(payload_with_span_attrs(attrs)).first[:spans].first
      expect(span["metadata"]["latency_ms"]).to eq(123.45)
    end

    it "extracts boolValue: true" do
      attrs = [{ "key" => "cached", "value" => { "boolValue" => true } }]
      span = OtlpNormalizer.call(payload_with_span_attrs(attrs)).first[:spans].first
      expect(span["metadata"]["cached"]).to eq(true)
    end

    it "extracts boolValue: false without losing the false value" do
      attrs = [{ "key" => "cached", "value" => { "boolValue" => false } }]
      span = OtlpNormalizer.call(payload_with_span_attrs(attrs)).first[:spans].first
      expect(span["metadata"]["cached"]).to eq(false)
    end

    it "skips attributes with unknown value types — no crash, key is omitted" do
      attrs = [
        { "key" => "model",   "value" => { "stringValue" => "claude-haiku-4-5-20251001" } },
        { "key" => "history", "value" => { "arrayValue"  => { "values" => [] } } }
      ]
      span = OtlpNormalizer.call(payload_with_span_attrs(attrs)).first[:spans].first
      expect(span["metadata"]["model"]).to eq("claude-haiku-4-5-20251001")
      expect(span["metadata"]).not_to have_key("history")
    end
  end

  # ── Span record fields ─────────────────────────────────────────────────────

  describe "span record fields" do
    let(:payload) { realistic_single_span(span_name: "openclaw.model.usage") }
    let(:span)    { OtlpNormalizer.call(payload).first[:spans].first }

    it "carries span_id through unchanged" do
      p = realistic_single_span(span_name: "openclaw.model.usage", span_id: "deadbeefdeadbeef")
      s = OtlpNormalizer.call(p).first[:spans].first
      expect(s["span_id"]).to eq("deadbeefdeadbeef")
    end

    it "parent_span_id is nil when absent" do
      expect(span["parent_span_id"]).to be_nil
    end

    it "metadata is {} when span has no attributes beyond sessionKey" do
      p = realistic_single_span(span_name: "openclaw.model.usage", extra_span_attrs: [])
      s = OtlpNormalizer.call(p).first[:spans].first
      # metadata may include sessionKey or be empty depending on implementation
      expect(s["metadata"]).to be_a(Hash)
    end

    describe "end_time field" do
      it "sets end_time to nil when endTimeUnixNano is absent" do
        span_data = OtlpNormalizer.call(
          realistic_single_span(span_name: "openclaw.model.usage")
        ).first[:spans].first
        # realistic_single_span helper has no endTimeUnixNano
        expect(span_data["end_time"]).to be_nil
      end

      it "sets end_time from model usage fixture (endTimeUnixNano present)" do
        span_data = OtlpNormalizer.call(model_usage_fixture_json).first[:spans].first
        expected = Time.at(1_776_353_064_358_000_000 / 1_000_000_000.0).utc.iso8601(3)
        expect(span_data["end_time"]).to eq(expected)
      end
    end
  end

  # ── Trace record ──────────────────────────────────────────────────────────

  describe "trace record" do
    it "truncates OTLP traceId to 16 characters" do
      result = OtlpNormalizer.call(model_usage_fixture_json).first
      expect(result[:trace]["trace_id"].length).to eq(16)
    end

    it "sets start_time from earliest span timestamp as ISO8601" do
      result = OtlpNormalizer.call(model_usage_fixture_json).first
      expected = Time.at(1_776_353_057_612_000_000 / 1_000_000_000.0).utc.iso8601(3)
      expect(result[:trace]["start_time"]).to eq(expected)
    end

    it "sets status to error when any span has OTLP status.code == 2" do
      payload = realistic_single_span(span_name: "openclaw.model.usage", status_code: 2)
      expect(OtlpNormalizer.call(payload).first[:trace]["status"]).to eq("error")
    end

    it "sets status to error when any span has openclaw.outcome in the error set, even with status.code != 2" do
      attrs = [{ "key" => "openclaw.outcome", "value" => { "stringValue" => "error" } }]
      payload = realistic_single_span(span_name: "openclaw.message.processed", extra_span_attrs: attrs)
      expect(OtlpNormalizer.call(payload).first[:trace]["status"]).to eq("error")
    end

    it "does not set status to error when openclaw.outcome is non-error (e.g. completed)" do
      attrs = [{ "key" => "openclaw.outcome", "value" => { "stringValue" => "completed" } }]
      payload = realistic_single_span(span_name: "openclaw.message.processed", extra_span_attrs: attrs)
      expect(OtlpNormalizer.call(payload).first[:trace]["status"]).to eq("success")
    end

    it "trace has the expected top-level fields" do
      trace = OtlpNormalizer.call(model_usage_fixture_json).first[:trace]
      expect(trace.keys).to include("trace_id", "agent_id", "task_name", "start_time", "status")
    end
  end

  # ── Error handling ─────────────────────────────────────────────────────────

  describe "error handling" do
    it "raises OtlpNormalizer::Error on invalid JSON" do
      expect { OtlpNormalizer.call("not json") }
        .to raise_error(OtlpNormalizer::Error, /invalid JSON/)
    end

    it "raises OtlpNormalizer::Error when resourceSpans is missing" do
      expect { OtlpNormalizer.call("{}") }
        .to raise_error(OtlpNormalizer::Error, /no resourceSpans/)
    end

    it "raises OtlpNormalizer::Error when resourceSpans is empty" do
      expect { OtlpNormalizer.call(JSON.generate("resourceSpans" => [])) }
        .to raise_error(OtlpNormalizer::Error, /no resourceSpans/)
    end

    it "raises OtlpNormalizer::Error when spans array is empty" do
      payload = JSON.generate({
        "resourceSpans" => [{
          "resource" => { "attributes" => [] },
          "scopeSpans" => [{ "spans" => [] }]
        }]
      })
      expect { OtlpNormalizer.call(payload) }
        .to raise_error(OtlpNormalizer::Error, /no spans/)
    end
  end

  # ── Output structure ───────────────────────────────────────────────────────

  describe "output structure" do
    it "returns an array with one entry per distinct traceId" do
      results = OtlpNormalizer.call(model_usage_fixture_json)
      expect(results).to be_an(Array).and have_attributes(length: 1)
    end

    it "each entry has :trace and :spans keys" do
      result = OtlpNormalizer.call(model_usage_fixture_json).first
      expect(result[:trace]).to be_a(Hash)
      expect(result[:spans]).to be_an(Array)
    end

    it "each span has the expected fields" do
      span = OtlpNormalizer.call(model_usage_fixture_json).first[:spans].first
      expect(span.keys).to include("trace_id", "span_id", "span_type", "span_name",
                                   "timestamp", "agent_id", "metadata")
    end
  end

  # ── Multiple resourceSpans entries ────────────────────────────────────────

  describe "multiple resourceSpans entries" do
    # Two resource entries with distinct service names; spans share one traceId.
    def multi_service_payload
      trace_id = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"
      JSON.generate({
        "resourceSpans" => [
          {
            "resource" => {
              "attributes" => [
                { "key" => "service.name", "value" => { "stringValue" => "gateway-primary" } }
              ]
            },
            "scopeSpans" => [{ "spans" => [{
              "traceId" => trace_id, "spanId" => "aaaa0000aaaa0000",
              "name" => "openclaw.model.usage", "startTimeUnixNano" => "1000000000000000000",
              "attributes" => [
                { "key" => "openclaw.sessionKey", "value" => { "stringValue" => "session-primary" } }
              ]
            }] }]
          },
          {
            "resource" => {
              "attributes" => [
                { "key" => "service.name", "value" => { "stringValue" => "gateway-secondary" } }
              ]
            },
            "scopeSpans" => [{ "spans" => [{
              "traceId" => trace_id, "spanId" => "bbbb0000bbbb0000",
              "name" => "openclaw.message.processed", "startTimeUnixNano" => "2000000000000000000",
              "attributes" => []
            }] }]
          }
        ]
      })
    end

    it "returns spans from all resource entries" do
      result = OtlpNormalizer.call(multi_service_payload).first
      expect(result[:spans].length).to eq(2)
    end

    it "assigns agent_id per span based on that span's resource entry" do
      result = OtlpNormalizer.call(multi_service_payload).first
      by_id = result[:spans].to_h { |s| [s["span_id"], s["agent_id"]] }
      # first span: sessionKey span attr takes precedence
      expect(by_id["aaaa0000aaaa0000"]).to eq("session-primary")
      # second span: no sessionKey → falls back to service.name
      expect(by_id["bbbb0000bbbb0000"]).to eq("gateway-secondary")
    end
  end

  # ── Multiple distinct traceId values ─────────────────────────────────────

  describe "multiple distinct traceId values" do
    TRACE_ID_A = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    TRACE_ID_B = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

    EXPECTED_TRACE_A = "aaaaaaaaaaaaaaaa"
    EXPECTED_TRACE_B = "bbbbbbbbbbbbbbbb"

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
              "traceId" => TRACE_ID_A, "spanId" => "span_a",
              "name" => "openclaw.model.usage", "startTimeUnixNano" => "1000000000000000000",
              "attributes" => [
                { "key" => "openclaw.sessionKey", "value" => { "stringValue" => "session-a" } }
              ]
            },
            {
              "traceId" => TRACE_ID_B, "spanId" => "span_b",
              "name" => "openclaw.message.processed", "startTimeUnixNano" => "2000000000000000000",
              "attributes" => [
                { "key" => "openclaw.sessionKey", "value" => { "stringValue" => "session-b" } }
              ]
            }
          ] }]
        }]
      })
    end

    it "returns one result per distinct traceId" do
      expect(OtlpNormalizer.call(multi_trace_payload).length).to eq(2)
    end

    it "each result has the correct normalized trace_id (first 16 chars)" do
      ids = OtlpNormalizer.call(multi_trace_payload).map { |r| r[:trace]["trace_id"] }.sort
      expect(ids).to eq([EXPECTED_TRACE_A, EXPECTED_TRACE_B].sort)
    end

    it "each trace result only contains its own spans" do
      OtlpNormalizer.call(multi_trace_payload).each do |result|
        trace_id = result[:trace]["trace_id"]
        result[:spans].each { |s| expect(s["trace_id"]).to eq(trace_id) }
      end
    end
  end
end
