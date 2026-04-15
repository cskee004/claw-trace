# Deletes Trace records (and their associated Spans) older than the given retention window.
# Logs associated with deleted traces are NOT removed — logs are managed independently.
#
# Usage:
#   result = TracePruner.call(retention_days: 30)
#   result[:deleted]  # => Integer count of deleted traces
class TracePruner
  def self.call(retention_days:)
    cutoff  = retention_days.to_i.days.ago
    old_ids = Trace.where("start_time < ?", cutoff).pluck(:trace_id)
    return { deleted: 0 } if old_ids.empty?

    Span.where(trace_id: old_ids).delete_all
    Trace.where(trace_id: old_ids).delete_all
    { deleted: old_ids.size }
  end
end
