# Represents a single instrumented operation within a Trace.
#
# Columns:
#   trace_id              (string)   foreign key matching Trace#trace_id
#   span_id               (string)   unique identifier for this span within its trace
#   parent_span_id        (string)   span_id of the parent span; nil for root spans
#   span_type             (string)   one of SPAN_TYPES; derived from OTLP span name prefix
#   timestamp             (datetime) when this span started
#   end_time              (datetime) when this span ended
#   span_name             (string)   OTLP span operation name (e.g. "openclaw.model.call")
#   agent_id              (string)   agent session key
#   metadata              (json)     arbitrary key-value pairs from OTLP span attributes
#   span_model            (string)   LLM model identifier (e.g. "claude-opus-4-5")
#   span_provider         (string)   LLM provider (e.g. "anthropic")
#   span_input_tokens     (integer)  prompt/input token count
#   span_output_tokens    (integer)  completion/output token count
#   span_cache_read_tokens  (integer) tokens read from prompt cache
#   span_cache_write_tokens (integer) tokens written to prompt cache
#   span_total_tokens     (integer)  total tokens consumed
#   span_outcome          (string)   terminal outcome (e.g. "completed", "error", "cancelled")
class Span < ApplicationRecord
  SPAN_TYPES = %w[
    model_call message_event tool_call session_event
    command_event webhook_event openclaw_event span
  ].freeze

  belongs_to :trace, foreign_key: :trace_id, primary_key: :trace_id, inverse_of: :spans

  validates :span_id,   presence: true, uniqueness: { scope: :trace_id }
  validates :span_type, presence: true, inclusion: { in: SPAN_TYPES }
  validates :timestamp, presence: true
  validates :agent_id,  presence: true
  validates :metadata,  exclusion: { in: [nil], message: "can't be nil" }
end
