Rails.application.config.after_initialize do
  next if Rails.env.test?
  defaults = {
    "log_retention_days"    => "30",
    "trace_retention_days"  => "30",
    "metric_retention_days" => "30",
  }

  defaults.each do |key, value|
    Setting.set(key, value) unless Setting.find_by(key: key)
  end
rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
  # Table doesn't exist yet (e.g. before db:migrate on first install) — skip.
end
