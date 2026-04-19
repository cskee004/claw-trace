# Translates an OTLP ExportMetricsServiceRequest JSON payload into an array of
# attribute hashes ready for Metric.insert_all!
#
# Only sum and gauge data points are stored. Histogram data points are dropped at
# ingestion — bucket arrays are too large to accumulate meaningfully, and span
# durations in the traces table already cover latency analysis.
#
# Returns [] for empty or missing resourceMetrics — never raises on absent data.
# Raises MetricsNormalizer::Error on malformed JSON.
class MetricsNormalizer
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
    Array(@payload["resourceMetrics"]).flat_map do |rm|
      resource_attrs = attrs_to_hash(rm.dig("resource", "attributes") || [])
      trace_id       = resource_attrs["trace_id"]

      (rm["scopeMetrics"] || []).flat_map do |sm|
        (sm["metrics"] || []).flat_map do |metric|
          normalize_metric(metric, trace_id)
        end
      end
    end
  end

  private

  def normalize_metric(metric, trace_id)
    name = metric["name"]
    return [] if name.blank?

    if metric["sum"]
      normalize_data_points(metric["sum"]["dataPoints"] || [], name, "sum", trace_id)
    elsif metric["gauge"]
      normalize_data_points(metric["gauge"]["dataPoints"] || [], name, "gauge", trace_id)
    else
      [] # histograms and unknown types are dropped at ingestion
    end
  end

  def normalize_data_points(data_points, name, type, trace_id)
    data_points.map do |dp|
      {
        "metric_name"       => name,
        "metric_type"       => type,
        "trace_id"          => trace_id,
        "metric_attributes" => attrs_to_hash(dp["attributes"] || []),
        "data_points"       => { "value" => dp["asInt"] || dp["asDouble"],
                                 "start_time" => nano_to_iso8601(dp["startTimeUnixNano"]) }.compact,
        "timestamp"         => nano_to_iso8601(dp["timeUnixNano"])
      }
    end
  end

  # Flattens OTLP's [{key, value: {stringValue|intValue|doubleValue|boolValue}}]
  # into a plain {"key" => scalar} hash. Uses key? to correctly handle boolValue: false.
  def attrs_to_hash(attrs)
    attrs.each_with_object({}) do |attr, hash|
      key   = attr["key"]
      value = attr["value"] || {}
      hash[key] = %w[stringValue intValue doubleValue boolValue]
                    .find { |type| value.key?(type) }
                    .then { |type| type ? value[type] : nil }
    end
  end

  def nano_to_iso8601(nano)
    return nil if nano.nil?

    Time.at(nano.to_i / 1_000_000_000.0).utc.iso8601(3)
  end
end
