# frozen_string_literal: true

# Dumps OTLP payloads (as JSON) to log/otlp_dumps/ for debugging.
#
# Called after protobuf decoding so the file always contains readable JSON,
# regardless of whether OpenClaw sent protobuf or JSON over the wire.
#
# Activated by setting CLAWTRACE_DUMP_PAYLOADS=1 in the environment.
#
# Usage in controllers (after body is resolved to a JSON string):
#   OtlpPayloadDumper.dump(:traces, json_body)
#
# Output files:
#   log/otlp_dumps/20260416_153042_123_traces.json
#   log/otlp_dumps/20260416_153042_456_metrics.json
#   log/otlp_dumps/20260416_153042_789_logs.json
#
# To enable:
#   CLAWTRACE_DUMP_PAYLOADS=1 rails server
#
# To inspect:
#   cat log/otlp_dumps/<file>.json | jq .
module OtlpPayloadDumper
  DUMP_DIR = Rails.root.join("log", "otlp_dumps")

  def self.dump(kind, json_body)
    return unless ENV["CLAWTRACE_DUMP_PAYLOADS"].present?
    return if json_body.blank?

    FileUtils.mkdir_p(DUMP_DIR)

    timestamp = Time.now.utc.strftime("%Y%m%d_%H%M%S_%3N")
    path      = DUMP_DIR.join("#{timestamp}_#{kind}.json")

    pretty = begin
      JSON.pretty_generate(JSON.parse(json_body))
    rescue JSON::ParserError
      json_body
    end

    File.write(path, pretty)
    Rails.logger.info("[OtlpPayloadDumper] #{kind} → #{path} (#{json_body.bytesize} bytes)")
  rescue => e
    Rails.logger.warn("[OtlpPayloadDumper] failed to write dump: #{e.message}")
  end
end
