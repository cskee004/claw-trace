# Represents a single instrumented operation within a Trace.
#
# Columns:
#   trace_id       (string)   foreign key matching Trace#trace_id
#   span_id        (string)   unique identifier for this span within its trace
#   parent_span_id (string)   span_id of the parent span; nil for root spans
#   span_type      (string)   one of SPAN_TYPES
#   timestamp      (datetime) when this span started
#   end_time       (datetime) when this span ended; nil for Bearer-token-ingested spans
#   name           (string)   OTLP span operation name (e.g. "agent.turn.process"); nil for Bearer-token spans
#   agent_id       (string)   agent session key
#   metadata       (json)     arbitrary key-value pairs from OTLP span attributes
class Span < ApplicationRecord
  SPAN_TYPES = %w[
    agent_run_started model_call model_response tool_call
    tool_result decision error run_completed
  ].freeze

  belongs_to :trace, foreign_key: :trace_id, primary_key: :trace_id, inverse_of: :spans

  validates :span_id,   presence: true, uniqueness: { scope: :trace_id }
  validates :span_type, presence: true, inclusion: { in: SPAN_TYPES }
  validates :timestamp, presence: true
  validates :agent_id,  presence: true
  validates :metadata,  exclusion: { in: [nil], message: "can't be nil" }
end
