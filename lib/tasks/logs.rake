namespace :logs do
  desc "Prune log records older than the configured retention window (default: 30 days)"
  task prune: :environment do
    retention_days = Setting.get("log_retention_days", default: "30").to_i
    result         = LogPruner.call(retention_days: retention_days)
    puts "Pruned #{result[:deleted]} log records older than #{retention_days} days."
  end
end
