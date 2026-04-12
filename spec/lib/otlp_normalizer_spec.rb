require "rails_helper"

RSpec.describe OtlpNormalizer do
  # ── Fixture helpers ────────────────────────────────────────────────────────

  OTLP_TRACE_ID = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6" # 32-char hex
  EXPECTED_TRACE_ID = "a1b2c3d4e5f6a7b8"               # first 16 chars

  def otlp_payload(spans:, session_key: "support-agent", extra_resource_attrs: [])
    JSON.generate({
      "resourceSpans" => [{
        "resource" => {
          "attributes" => [
            { "key" => "openclaw.session.key", "value" => { "stringValue" => session_key } }
          ] + extra_resource_attrs
        },
        "scopeSpans" => [{ "spans" => spans }]
      }]
    })
  end

  def otlp_span(name:, span_id:, timestamp_ns:, parent_span_id: nil, status_code: nil,
                attributes: [], end_timestamp_ns: nil)
    span = {
      "traceId"            => OTLP_TRACE_ID,
      "spanId"             => span_id,
      "name"               => name,
      "startTimeUnixNano"  => timestamp_ns.to_s,
      "attributes"         => attributes
    }
    span["parentSpanId"]    = parent_span_id            if parent_span_id
    span["status"]          = { "code" => status_code } if status_code
    span["endTimeUnixNano"] = end_timestamp_ns.to_s     if end_timestamp_ns
    span
  end

  # Returns OtlpNormalizer output as an array: [trace_hash, *span_hashes].
  # Index 0 is the trace record; index 1+ are span records.
  def normalize_and_parse(json_string)
    result = OtlpNormalizer.call(json_string)
    [result[:trace]] + result[:spans]
  end

  # ── Span type mapping ──────────────────────────────────────────────────────

  describe "span type mapping" do
    # Two-span helper: the tested span comes first (lower timestamp) so it gets
    # a name-based mapping; the trailing span gets run_completed as the final span.
    def two_span_payload(name:, status_code: nil)
      tested = otlp_span(name: name, span_id: "aaaa0000aaaa0000", timestamp_ns: 1_000_000_000_000_000_000,
                         status_code: status_code)
      final  = otlp_span(name: "openclaw.request", span_id: "bbbb0000bbbb0000",
                         parent_span_id: "aaaa0000aaaa0000", timestamp_ns: 2_000_000_000_000_000_000)
      otlp_payload(spans: [tested, final])
    end

    it "maps openclaw.request → agent_run_started" do
      payload = otlp_payload(spans: [
        otlp_span(name: "openclaw.request",   span_id: "aaaa0000aaaa0000", timestamp_ns: 1_000_000_000_000_000_000),
        otlp_span(name: "openclaw.agent.turn", span_id: "bbbb0000bbbb0000",
                  parent_span_id: "aaaa0000aaaa0000", timestamp_ns: 2_000_000_000_000_000_000)
      ])
      lines = normalize_and_parse(payload)
      expect(lines[1]["span_type"]).to eq("agent_run_started")
    end

    it "maps openclaw.agent.turn → model_call" do
      lines = normalize_and_parse(two_span_payload(name: "openclaw.agent.turn"))
      expect(lines[1]["span_type"]).to eq("model_call")
    end

    it "maps tool.* → tool_call" do
      lines = normalize_and_parse(two_span_payload(name: "tool.web_search"))
      expect(lines[1]["span_type"]).to eq("tool_call")
    end

    it "maps a different tool.* name → tool_call" do
      lines = normalize_and_parse(two_span_payload(name: "tool.read_file"))
      expect(lines[1]["span_type"]).to eq("tool_call")
    end

    it "maps openclaw.command.* → decision" do
      lines = normalize_and_parse(two_span_payload(name: "openclaw.command.execute"))
      expect(lines[1]["span_type"]).to eq("decision")
    end

    it "maps the final span (highest timestamp) → run_completed" do
      lines = normalize_and_parse(two_span_payload(name: "openclaw.agent.turn"))
      final_span_line = lines.last
      expect(final_span_line["span_type"]).to eq("run_completed")
    end

    it "maps ERROR status (code 2) → error, overriding name-based mapping" do
      lines = normalize_and_parse(two_span_payload(name: "openclaw.request", status_code: 2))
      expect(lines[1]["span_type"]).to eq("error")
    end

    it "maps ERROR status on the final span → error (not run_completed)" do
      payload = otlp_payload(spans: [
        otlp_span(name: "openclaw.request", span_id: "aaaa0000aaaa0000", timestamp_ns: 1_000_000_000_000_000_000),
        otlp_span(name: "openclaw.agent.turn", span_id: "bbbb0000bbbb0000",
                  parent_span_id: "aaaa0000aaaa0000",
                  timestamp_ns: 2_000_000_000_000_000_000, status_code: 2)
      ])
      lines = normalize_and_parse(payload)
      expect(lines.last["span_type"]).to eq("error")
    end

    it "falls back to model_call for unrecognised span names" do
      lines = normalize_and_parse(two_span_payload(name: "openclaw.unknown.thing"))
      expect(lines[1]["span_type"]).to eq("model_call")
    end
  end

  # ── Trace record ──────────────────────────────────────────────────────────

  describe "trace record (line 1)" do
    let(:single_span_payload) do
      otlp_payload(spans: [
        otlp_span(name: "openclaw.request", span_id: "aaaa0000aaaa0000",
                  timestamp_ns: 1_712_345_678_000_000_000)
      ])
    end

    it "truncates OTLP traceId to 16 characters" do
      lines = normalize_and_parse(single_span_payload)
      expect(lines[0]["trace_id"]).to eq(EXPECTED_TRACE_ID)
      expect(lines[0]["trace_id"].length).to eq(16)
    end

    it "reads agent_id from openclaw.session.key resource attribute" do
      lines = normalize_and_parse(single_span_payload)
      expect(lines[0]["agent_id"]).to eq("support-agent")
    end

    it "falls back to service.name when openclaw.session.key is absent" do
      payload = JSON.generate({
        "resourceSpans" => [{
          "resource" => {
            "attributes" => [
              { "key" => "service.name", "value" => { "stringValue" => "my-openai-agent" } }
            ]
          },
          "scopeSpans" => [{ "spans" => [
            otlp_span(name: "openclaw.request", span_id: "aaaa0000aaaa0000",
                      timestamp_ns: 1_000_000_000_000_000_000)
          ] }]
        }]
      })
      lines = normalize_and_parse(payload)
      expect(lines[0]["agent_id"]).to eq("my-openai-agent")
    end

    it "falls back to 'unknown' when neither openclaw.session.key nor service.name is present" do
      payload = JSON.generate({
        "resourceSpans" => [{
          "resource" => { "attributes" => [] },
          "scopeSpans" => [{ "spans" => [
            otlp_span(name: "openclaw.request", span_id: "aaaa0000aaaa0000",
                      timestamp_ns: 1_000_000_000_000_000_000)
          ] }]
        }]
      })
      lines = normalize_and_parse(payload)
      expect(lines[0]["agent_id"]).to eq("unknown")
    end

    it "sets task_name from the root span (no parentSpanId)" do
      payload = otlp_payload(spans: [
        otlp_span(name: "openclaw.request", span_id: "aaaa0000aaaa0000",
                  timestamp_ns: 1_000_000_000_000_000_000),
        otlp_span(name: "openclaw.agent.turn", span_id: "bbbb0000bbbb0000",
                  parent_span_id: "aaaa0000aaaa0000", timestamp_ns: 2_000_000_000_000_000_000)
      ])
      lines = normalize_and_parse(payload)
      expect(lines[0]["task_name"]).to eq("openclaw.request")
    end

    it "sets start_time from the earliest span timestamp as ISO8601" do
      payload = otlp_payload(spans: [
        otlp_span(name: "openclaw.agent.turn", span_id: "bbbb0000bbbb0000",
                  timestamp_ns: 2_000_000_000_000_000_000),
        otlp_span(name: "openclaw.request", span_id: "aaaa0000aaaa0000",
                  timestamp_ns: 1_000_000_000_000_000_000)
      ])
      lines = normalize_and_parse(payload)
      expected_time = Time.at(1_000_000_000.0).utc.iso8601(3)
      expect(lines[0]["start_time"]).to eq(expected_time)
    end

    it "sets status to success when no spans have an error status" do
      lines = normalize_and_parse(single_span_payload)
      expect(lines[0]["status"]).to eq("success")
    end

    it "sets status to error when any span has OTLP error code 2" do
      payload = otlp_payload(spans: [
        otlp_span(name: "openclaw.request", span_id: "aaaa0000aaaa0000",
                  timestamp_ns: 1_000_000_000_000_000_000, status_code: 2)
      ])
      lines = normalize_and_parse(payload)
      expect(lines[0]["status"]).to eq("error")
    end
  end

  # ── Span record fields ─────────────────────────────────────────────────────

  describe "span record fields" do
    it "sets trace_id on every span record" do
      payload = otlp_payload(spans: [
        otlp_span(name: "openclaw.request", span_id: "aaaa0000aaaa0000", timestamp_ns: 1_000_000_000_000_000_000)
      ])
      lines = normalize_and_parse(payload)
      expect(lines[1]["trace_id"]).to eq(EXPECTED_TRACE_ID)
    end

    it "converts nanosecond timestamp to ISO8601" do
      payload = otlp_payload(spans: [
        otlp_span(name: "openclaw.request", span_id: "aaaa0000aaaa0000",
                  timestamp_ns: 1_712_345_678_500_000_000)
      ])
      lines = normalize_and_parse(payload)
      expected = Time.at(1_712_345_678.5).utc.iso8601(3)
      expect(lines[1]["timestamp"]).to eq(expected)
    end

    it "carries span_id through unchanged" do
      payload = otlp_payload(spans: [
        otlp_span(name: "openclaw.request", span_id: "deadbeefdeadbeef", timestamp_ns: 1_000_000_000_000_000_000)
      ])
      lines = normalize_and_parse(payload)
      expect(lines[1]["span_id"]).to eq("deadbeefdeadbeef")
    end

    it "sets parent_span_id when present" do
      payload = otlp_payload(spans: [
        otlp_span(name: "openclaw.request",    span_id: "aaaa0000aaaa0000", timestamp_ns: 1_000_000_000_000_000_000),
        otlp_span(name: "openclaw.agent.turn", span_id: "bbbb0000bbbb0000",
                  parent_span_id: "aaaa0000aaaa0000", timestamp_ns: 2_000_000_000_000_000_000)
      ])
      lines = normalize_and_parse(payload)
      expect(lines[2]["parent_span_id"]).to eq("aaaa0000aaaa0000")
    end

    it "sets parent_span_id to nil when absent" do
      payload = otlp_payload(spans: [
        otlp_span(name: "openclaw.request", span_id: "aaaa0000aaaa0000", timestamp_ns: 1_000_000_000_000_000_000)
      ])
      lines = normalize_and_parse(payload)
      expect(lines[1]["parent_span_id"]).to be_nil
    end

    it "sets metadata to {} when span has no attributes" do
      payload = otlp_payload(spans: [
        otlp_span(name: "openclaw.request", span_id: "aaaa0000aaaa0000",
                  timestamp_ns: 1_000_000_000_000_000_000, attributes: [])
      ])
      lines = normalize_and_parse(payload)
      expect(lines[1]["metadata"]).to eq({})
    end

    describe "end_time field" do
      it "sets end_time to ISO8601 when endTimeUnixNano is present" do
        payload = otlp_payload(spans: [
          otlp_span(name: "openclaw.request", span_id: "aaaa0000aaaa0000",
                    timestamp_ns: 1_000_000_000_000_000_000,
                    end_timestamp_ns: 1_000_000_001_500_000_000)
        ])
        span = OtlpNormalizer.call(payload)[:spans].first
        expected = Time.at(1_000_000_001.5).utc.iso8601(3)
        expect(span["end_time"]).to eq(expected)
      end

      it "sets end_time to nil when endTimeUnixNano is absent" do
        payload = otlp_payload(spans: [
          otlp_span(name: "openclaw.request", span_id: "aaaa0000aaaa0000",
                    timestamp_ns: 1_000_000_000_000_000_000)
        ])
        span = OtlpNormalizer.call(payload)[:spans].first
        expect(span["end_time"]).to be_nil
      end

      it "sets end_time to nil when endTimeUnixNano is zero (protobuf default)" do
        payload = otlp_payload(spans: [
          otlp_span(name: "openclaw.request", span_id: "aaaa0000aaaa0000",
                    timestamp_ns: 1_000_000_000_000_000_000,
                    end_timestamp_ns: 0)
        ])
        span = OtlpNormalizer.call(payload)[:spans].first
        expect(span["end_time"]).to be_nil
      end
    end

    it "includes the OTLP span name in the span record" do
      payload = otlp_payload(spans: [
        otlp_span(name: "tool.web_search", span_id: "aaaa0000aaaa0000",
                  timestamp_ns: 1_000_000_000_000_000_000)
      ])
      span = OtlpNormalizer.call(payload)[:spans].first
      expect(span["span_name"]).to eq("tool.web_search")
    end
  end

  # ── attrs_to_hash ──────────────────────────────────────────────────────────

  describe "attrs_to_hash (via span metadata)" do
    def payload_with_span_attrs(attrs)
      otlp_payload(spans: [
        otlp_span(name: "openclaw.request", span_id: "aaaa0000aaaa0000",
                  timestamp_ns: 1_000_000_000_000_000_000, attributes: attrs)
      ])
    end

    it "extracts stringValue" do
      attrs = [{ "key" => "model", "value" => { "stringValue" => "gpt-4o" } }]
      lines = normalize_and_parse(payload_with_span_attrs(attrs))
      expect(lines[1]["metadata"]["model"]).to eq("gpt-4o")
    end

    it "extracts intValue" do
      attrs = [{ "key" => "tokens", "value" => { "intValue" => 512 } }]
      lines = normalize_and_parse(payload_with_span_attrs(attrs))
      expect(lines[1]["metadata"]["tokens"]).to eq(512)
    end

    it "extracts doubleValue" do
      attrs = [{ "key" => "latency_ms", "value" => { "doubleValue" => 123.45 } }]
      lines = normalize_and_parse(payload_with_span_attrs(attrs))
      expect(lines[1]["metadata"]["latency_ms"]).to eq(123.45)
    end

    it "extracts boolValue: true" do
      attrs = [{ "key" => "cached", "value" => { "boolValue" => true } }]
      lines = normalize_and_parse(payload_with_span_attrs(attrs))
      expect(lines[1]["metadata"]["cached"]).to eq(true)
    end

    it "extracts boolValue: false without losing the false value" do
      attrs = [{ "key" => "cached", "value" => { "boolValue" => false } }]
      lines = normalize_and_parse(payload_with_span_attrs(attrs))
      expect(lines[1]["metadata"]["cached"]).to eq(false)
    end

    it "handles multiple attributes on one span" do
      attrs = [
        { "key" => "model",  "value" => { "stringValue" => "claude-3" } },
        { "key" => "tokens", "value" => { "intValue" => 256 } }
      ]
      lines = normalize_and_parse(payload_with_span_attrs(attrs))
      expect(lines[1]["metadata"]).to eq("model" => "claude-3", "tokens" => 256)
    end

    it "skips attributes with unknown value types — no crash, no nil key" do
      attrs = [
        { "key" => "model",   "value" => { "stringValue" => "gpt-4o" } },
        { "key" => "history", "value" => { "arrayValue"  => { "values" => [] } } }
      ]
      lines = normalize_and_parse(payload_with_span_attrs(attrs))
      metadata = lines[1]["metadata"]
      expect(metadata["model"]).to eq("gpt-4o")
      expect(metadata).not_to have_key("history")
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
      payload = otlp_payload(spans: [])
      expect { OtlpNormalizer.call(payload) }
        .to raise_error(OtlpNormalizer::Error, /no spans/)
    end
  end

  # ── Output structure ───────────────────────────────────────────────────────

  describe "output structure" do
    it "returns a hash with :trace and :spans keys" do
      payload = otlp_payload(spans: [
        otlp_span(name: "openclaw.request",    span_id: "aaaa0000aaaa0000", timestamp_ns: 1_000_000_000_000_000_000),
        otlp_span(name: "openclaw.agent.turn", span_id: "bbbb0000bbbb0000",
                  parent_span_id: "aaaa0000aaaa0000", timestamp_ns: 2_000_000_000_000_000_000)
      ])
      result = OtlpNormalizer.call(payload)
      expect(result).to be_a(Hash)
      expect(result[:trace]).to be_a(Hash)
      expect(result[:spans]).to be_an(Array).and have_attributes(length: 2)
    end

    it "trace has the expected fields" do
      payload = otlp_payload(spans: [
        otlp_span(name: "openclaw.request", span_id: "aaaa0000aaaa0000", timestamp_ns: 1_000_000_000_000_000_000)
      ])
      trace = OtlpNormalizer.call(payload)[:trace]
      expect(trace.keys).to include("trace_id", "agent_id", "task_name", "start_time", "status")
    end

    it "each span has the expected fields" do
      payload = otlp_payload(spans: [
        otlp_span(name: "openclaw.request", span_id: "aaaa0000aaaa0000", timestamp_ns: 1_000_000_000_000_000_000)
      ])
      span = OtlpNormalizer.call(payload)[:spans].first
      expect(span.keys).to include("trace_id", "span_id", "span_type", "span_name", "timestamp", "agent_id", "metadata")
    end
  end

  # ── Multiple resourceSpans entries ────────────────────────────────────────

  describe "multiple resourceSpans entries" do
    # Two resource entries in one payload; spans share the same traceId.
    # Entry 1: payment-service with openclaw.session.key; one root span.
    # Entry 2: notification-service (service.name only); one child span.
    def multi_service_payload
      JSON.generate({
        "resourceSpans" => [
          {
            "resource" => {
              "attributes" => [
                { "key" => "openclaw.session.key", "value" => { "stringValue" => "payment-service" } }
              ]
            },
            "scopeSpans" => [{ "spans" => [
              otlp_span(name: "openclaw.request", span_id: "aaaa0000aaaa0000",
                        timestamp_ns: 1_000_000_000_000_000_000)
            ]}]
          },
          {
            "resource" => {
              "attributes" => [
                { "key" => "service.name", "value" => { "stringValue" => "notification-service" } }
              ]
            },
            "scopeSpans" => [{ "spans" => [
              otlp_span(name: "openclaw.agent.turn", span_id: "bbbb0000bbbb0000",
                        parent_span_id: "aaaa0000aaaa0000",
                        timestamp_ns: 2_000_000_000_000_000_000)
            ]}]
          }
        ]
      })
    end

    it "returns spans from all resource entries, not just the first" do
      result = OtlpNormalizer.call(multi_service_payload)
      expect(result[:spans].length).to eq(2)
    end

    it "assigns agent_id per resource entry to each span" do
      result = OtlpNormalizer.call(multi_service_payload)
      span_ids_to_agents = result[:spans].to_h { |s| [s["span_id"], s["agent_id"]] }
      expect(span_ids_to_agents["aaaa0000aaaa0000"]).to eq("payment-service")
      expect(span_ids_to_agents["bbbb0000bbbb0000"]).to eq("notification-service")
    end

    it "uses the first resource entry's agent_id for the trace record" do
      result = OtlpNormalizer.call(multi_service_payload)
      expect(result[:trace]["agent_id"]).to eq("payment-service")
    end
  end
end
