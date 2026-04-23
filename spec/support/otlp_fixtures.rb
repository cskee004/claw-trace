module OtlpFixtures
  FIXTURE_DIR = Rails.root.join("spec/fixtures/otlp")

  def model_usage_fixture_json
    File.read(FIXTURE_DIR.join("span-openclaw-model-usage-001.json"))
  end

  def message_processed_fixture_json
    File.read(FIXTURE_DIR.join("span-openclaw-message-processed-001.json"))
  end

  def log_fixture_json
    File.read(FIXTURE_DIR.join("log-openclaw-agent-execution-001.json"))
  end

  def webhook_processed_fixture_json
    File.read(FIXTURE_DIR.join("span-openclaw-webhook-processed-001.json"))
  end

  def webhook_error_fixture_json
    File.read(FIXTURE_DIR.join("span-openclaw-webhook-error-001.json"))
  end

  def session_stuck_fixture_json
    File.read(FIXTURE_DIR.join("span-openclaw-session-stuck-001.json"))
  end

  def agent_trace_fixture_json
    File.read(FIXTURE_DIR.join("otlp-agent-trace-fixture.json"))
  end

  # Builds a minimal single-span payload using real OpenClaw resource shape.
  # Used for testing pattern-based rules and structural behavior without
  # depending on the specific fixture span names.
  def realistic_single_span(span_name:, span_id: "aaaa0000aaaa0000",
                             session_key: "agent:main:discord:channel:test",
                             trace_id: "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6",
                             timestamp_ns: "1776353057612000000",
                             extra_span_attrs: [], status_code: nil)
    span = {
      "traceId"           => trace_id,
      "spanId"            => span_id,
      "name"              => span_name,
      "startTimeUnixNano" => timestamp_ns,
      "attributes"        => [
        { "key" => "openclaw.sessionKey", "value" => { "stringValue" => session_key } }
      ] + extra_span_attrs
    }
    span["status"] = { "code" => status_code } if status_code

    JSON.generate({
      "resourceSpans" => [{
        "resource" => {
          "attributes" => [
            { "key" => "host.name",                "value" => { "stringValue" => "VM-0-5-ubuntu" } },
            { "key" => "service.name",              "value" => { "stringValue" => "openclaw-gateway" } },
            { "key" => "process.executable.name",   "value" => { "stringValue" => "openclaw-gateway" } }
          ]
        },
        "scopeSpans" => [{ "spans" => [span] }]
      }]
    })
  end
end

RSpec.configure { |c| c.include OtlpFixtures }
