# Extracted from cskee004/log-analyzer. This copy is now independent — changes here
# do not sync back to the original repository.

module ApplicationHelper
  # Formats a duration in seconds as "X.Xs", or "—" if nil (no spans recorded).
  def format_duration(seconds)
    return "—" if seconds.nil?

    "#{seconds.round(1)}s"
  end
end
