# spec/lib/logs_normalizer_spec.rb
require "rails_helper"

RSpec.describe LogsNormalizer do
  BASE_TS      = 1_712_345_678_500_000_000
  EXPECTED_TS  = Time.at(BASE_TS / 1_000_000_000.0).utc.iso8601(3)

  # ── Fixture helpers ──────────────────────────────────────────────────────────

  def log_payload(log_records:, resource_attrs: [])
    JSON.generate({
      "resourceLogs" => [{
        "resource" => { "attributes" => resource_attrs },
        "scopeLogs" => [{ "logRecords" => log_records }]
      }]
    })
  end

  def log_record(timestamp_ns: BASE_TS, severity_text: nil, severity_number: nil,
                 body: nil, trace_id: nil, span_id: nil, attrs: [])
    record = {
      "timeUnixNano" => timestamp_ns.to_s,
      "attributes"   => attrs
    }
    record["severityText"]   = severity_text   if severity_text
    record["severityNumber"] = severity_number if severity_number
    record["body"]           = { "stringValue" => body } if body
    record["traceId"]        = trace_id if trace_id
    record["spanId"]         = span_id  if span_id
    record
  end

  def string_attr(key, value)
    { "key" => key, "value" => { "stringValue" => value } }
  end

  # ── Well-formed payload ──────────────────────────────────────────────────────

  describe "well-formed payload" do
    let(:payload) do
      log_payload(log_records: [
        log_record(
          severity_text:   "INFO",
          severity_number: 9,
          body:            "agent turn completed",
          trace_id:        "a1b2c3d4e5f6a7b8",
          span_id:         "s1a2b3c4d5e6f7a8",
          attrs:           [string_attr("service.name", "openclaw")]
        )
      ])
    end

    subject(:result) { LogsNormalizer.call(payload) }

    it "returns one hash per log record" do
      expect(result.length).to eq(1)
    end

    it "sets timestamp from timeUnixNano" do
      expect(result[0]["timestamp"]).to eq(EXPECTED_TS)
    end

    it "sets severity_text" do
      expect(result[0]["severity_text"]).to eq("INFO")
    end

    it "sets severity_number" do
      expect(result[0]["severity_number"]).to eq(9)
    end

    it "sets body from body.stringValue" do
      expect(result[0]["body"]).to eq("agent turn completed")
    end

    it "sets trace_id as lowercase hex" do
      expect(result[0]["trace_id"]).to eq("a1b2c3d4e5f6a7b8")
    end

    it "sets span_id as lowercase hex" do
      expect(result[0]["span_id"]).to eq("s1a2b3c4d5e6f7a8")
    end

    it "sets log_attributes from attributes" do
      expect(result[0]["log_attributes"]).to eq("service.name" => "openclaw")
    end
  end

  # ── Missing optional fields ──────────────────────────────────────────────────

  describe "missing optional fields" do
    it "returns nil trace_id when absent" do
      payload = log_payload(log_records: [log_record])
      expect(LogsNormalizer.call(payload)[0]["trace_id"]).to be_nil
    end

    it "returns nil span_id when absent" do
      payload = log_payload(log_records: [log_record])
      expect(LogsNormalizer.call(payload)[0]["span_id"]).to be_nil
    end

    it "returns nil body when absent" do
      payload = log_payload(log_records: [log_record])
      expect(LogsNormalizer.call(payload)[0]["body"]).to be_nil
    end

    it "returns nil severity_text when absent" do
      payload = log_payload(log_records: [log_record])
      expect(LogsNormalizer.call(payload)[0]["severity_text"]).to be_nil
    end

    it "returns nil severity_number when absent" do
      payload = log_payload(log_records: [log_record])
      expect(LogsNormalizer.call(payload)[0]["severity_number"]).to be_nil
    end

    it "returns empty hash for log_attributes when attributes key is absent" do
      record  = { "timeUnixNano" => BASE_TS.to_s }
      payload = JSON.generate("resourceLogs" => [{ "resource" => { "attributes" => [] },
                                                   "scopeLogs" => [{ "logRecords" => [record] }] }])
      expect(LogsNormalizer.call(payload)[0]["log_attributes"]).to eq({})
    end
  end

  # ── Unknown attribute value types ────────────────────────────────────────────

  describe "unknown attribute value types" do
    it "skips attributes with non-scalar value types — no crash, key is omitted" do
      attrs = [
        { "key" => "known",   "value" => { "stringValue" => "ok" } },
        { "key" => "unknown", "value" => { "arrayValue" => { "values" => [] } } }
      ]
      payload = log_payload(log_records: [log_record(attrs: attrs)])
      result  = LogsNormalizer.call(payload)[0]["log_attributes"]
      expect(result).to eq("known" => "ok")
      expect(result).not_to have_key("unknown")
    end
  end

  # ── Empty / missing input ─────────────────────────────────────────────────────

  describe "empty and missing input" do
    it "returns [] for empty resourceLogs array" do
      expect(LogsNormalizer.call(JSON.generate("resourceLogs" => []))).to eq([])
    end

    it "returns [] when resourceLogs key is absent" do
      expect(LogsNormalizer.call(JSON.generate({}))).to eq([])
    end

    it "returns [] when scopeLogs is empty" do
      payload = JSON.generate("resourceLogs" => [{
        "resource" => { "attributes" => [] },
        "scopeLogs" => []
      }])
      expect(LogsNormalizer.call(payload)).to eq([])
    end
  end

  # ── Multiple log records ──────────────────────────────────────────────────────

  describe "multiple log records" do
    it "returns one hash per log record across multiple scopeLogs" do
      payload = JSON.generate({
        "resourceLogs" => [{
          "resource" => { "attributes" => [] },
          "scopeLogs" => [
            { "logRecords" => [log_record, log_record] },
            { "logRecords" => [log_record] }
          ]
        }]
      })
      expect(LogsNormalizer.call(payload).length).to eq(3)
    end
  end

  # ── attrs_to_hash ─────────────────────────────────────────────────────────────

  describe "attrs_to_hash (via log_attributes)" do
    def payload_with_attrs(attrs)
      log_payload(log_records: [log_record(attrs: attrs)])
    end

    it "extracts stringValue" do
      attrs = [{ "key" => "model", "value" => { "stringValue" => "claude-sonnet-4-6" } }]
      expect(LogsNormalizer.call(payload_with_attrs(attrs))[0]["log_attributes"]["model"])
        .to eq("claude-sonnet-4-6")
    end

    it "extracts intValue" do
      attrs = [{ "key" => "tokens", "value" => { "intValue" => 512 } }]
      expect(LogsNormalizer.call(payload_with_attrs(attrs))[0]["log_attributes"]["tokens"]).to eq(512)
    end

    it "extracts doubleValue" do
      attrs = [{ "key" => "cost", "value" => { "doubleValue" => 0.0042 } }]
      expect(LogsNormalizer.call(payload_with_attrs(attrs))[0]["log_attributes"]["cost"]).to eq(0.0042)
    end

    it "extracts boolValue: true" do
      attrs = [{ "key" => "cached", "value" => { "boolValue" => true } }]
      expect(LogsNormalizer.call(payload_with_attrs(attrs))[0]["log_attributes"]["cached"]).to eq(true)
    end

    it "extracts boolValue: false without losing the false value" do
      attrs = [{ "key" => "cached", "value" => { "boolValue" => false } }]
      expect(LogsNormalizer.call(payload_with_attrs(attrs))[0]["log_attributes"]["cached"]).to eq(false)
    end
  end

  # ── Error handling ────────────────────────────────────────────────────────────

  describe "error handling" do
    it "raises LogsNormalizer::Error on invalid JSON" do
      expect { LogsNormalizer.call("not json") }
        .to raise_error(LogsNormalizer::Error, /invalid JSON/)
    end
  end
end
