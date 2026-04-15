# Deletes Log records older than the given retention window.
#
# Usage:
#   result = LogPruner.call(retention_days: 30)
#   result[:deleted]  # => Integer count of deleted records
class LogPruner
  def self.call(retention_days:)
    cutoff  = retention_days.to_i.days.ago
    deleted = Log.where("timestamp < ?", cutoff).delete_all
    { deleted: deleted }
  end
end
