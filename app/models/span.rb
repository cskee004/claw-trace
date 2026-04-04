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
