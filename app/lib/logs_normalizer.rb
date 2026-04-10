# app/lib/logs_normalizer.rb

# Translates an OTLP ExportLogsServiceRequest JSON payload into an array of
# attribute hashes ready for Log.insert_all!
#
# OTLP input:
#   {
#     "resourceLogs": [{
#       "resource": { "attributes": [{key, value}] },
#       "scopeLogs": [{ "logRecords": [{
#         "timeUnixNano": "...",
#         "severityText": "INFO",
#         "severityNumber": 9,
#         "body": { "stringValue": "..." },
#         "traceId": "a1b2c3d4e5f6a7b8",
#         "spanId": "ab12cd34ef56a1b2",
#         "attributes": [{key, value}]
#       }] }]
#     }]
#   }
#
# Output: array of hashes (one per log record), e.g.:
#   [
#     { "trace_id" => "a1b2c3d4e5f6a7b8", "span_id" => "ab12cd34ef56a1b2",
#       "severity_text" => "INFO", "severity_number" => 9,
#       "body" => "agent turn completed",
#       "log_attributes" => { "service.name" => "openclaw" },
#       "timestamp" => "2024-04-05T22:54:38.500Z" },
#     ...
#   ]
#
# Returns [] for empty or missing resourceLogs — never raises on absent data.
# Raises LogsNormalizer::Error on malformed JSON.
class LogsNormalizer
  Error = Class.new(StandardError)

  def self.call(json_string)
    new(json_string).call
  end

  def initialize(json_string)
    @payload = JSON.parse(json_string.to_s)
  rescue JSON::ParserError => e
    raise Error, "invalid JSON: #{e.message}"
  end

  def call
    Array(@payload["resourceLogs"]).flat_map do |rl|
      (rl["scopeLogs"] || []).flat_map do |sl|
        (sl["logRecords"] || []).map { |lr| normalize_log_record(lr) }
      end
    end
  end

  private

  def normalize_log_record(lr)
    {
      "trace_id"        => hex_or_nil(lr["traceId"]),
      "span_id"         => hex_or_nil(lr["spanId"]),
      "severity_text"   => lr["severityText"],
      "severity_number" => lr["severityNumber"],
      "body"            => lr.dig("body", "stringValue"),
      "log_attributes"  => attrs_to_hash(lr["attributes"] || []),
      "timestamp"       => nano_to_iso8601(lr["timeUnixNano"])
    }
  end

  def hex_or_nil(value)
    value.presence&.downcase
  end

  def nano_to_iso8601(nano)
    return nil if nano.nil?

    Time.at(nano.to_i / 1_000_000_000.0).utc.iso8601(3)
  end

  # Flattens OTLP's [{key, value: {stringValue|intValue|doubleValue|boolValue}}]
  # into a plain {"key" => scalar} hash. Uses key? to correctly handle boolValue: false.
  # Non-scalar types (arrayValue, kvlistValue, bytesValue) are deliberately omitted —
  # OpenClaw attributes were validated as scalar-only on 2026-04-10.
  def attrs_to_hash(attrs)
    attrs.each_with_object({}) do |attr, hash|
      key   = attr["key"]
      value = attr["value"] || {}
      type  = %w[stringValue intValue doubleValue boolValue].find { |t| value.key?(t) }
      hash[key] = value[type] if type
    end
  end
end
