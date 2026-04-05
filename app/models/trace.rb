class Trace < ApplicationRecord
  enum :status, { in_progress: 0, success: 1, error: 2 }

  has_many :spans, foreign_key: :trace_id, primary_key: :trace_id,
                   inverse_of: :trace, dependent: :destroy

  validates :trace_id,   presence: true, uniqueness: true, length: { is: 16 }
  validates :agent_id,   presence: true
  validates :task_name,  presence: true
  validates :start_time, presence: true
  validates :status,     presence: true

  def to_param
    trace_id
  end

  # Returns elapsed seconds as a Float, or nil if the trace has no spans.
  # Assumes spans are already eager-loaded; does not issue additional queries.
  def duration
    return nil if spans.empty?

    timestamps = spans.map(&:timestamp)
    timestamps.max - timestamps.min
  end
end
