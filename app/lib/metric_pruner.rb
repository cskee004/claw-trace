# Deletes Metric records older than the given retention window.
#
# Usage:
#   result = MetricPruner.call(retention_days: 30)
#   result[:deleted]  # => Integer count of deleted records
class MetricPruner
  def self.call(retention_days:)
    cutoff  = retention_days.to_i.days.ago
    deleted = Metric.where("timestamp < ?", cutoff).delete_all
    { deleted: deleted }
  end
end
