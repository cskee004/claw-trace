# Stores a single OTLP log record ingested from an OpenClaw agent.
#
# Columns:
#   trace_id        (string)   optional — hex trace identifier for correlation
#   span_id         (string)   optional — hex span identifier for correlation
#   severity_text   (string)   human-readable severity (e.g. "INFO", "WARN", "ERROR")
#   severity_number (integer)  OTLP numeric severity level (1–24); nil when absent
#   body            (text)     log message body; nil when absent
#   log_attributes  (json)     key-value pairs from OTLP log record attributes
#   timestamp       (datetime) when the log record was emitted
class Log < ApplicationRecord
  belongs_to :trace, foreign_key: :trace_id, primary_key: :trace_id,
                     inverse_of: :logs, optional: true

  validates :timestamp,      presence: true
  validates :log_attributes, exclusion: { in: [nil], message: "can't be nil" }
end
