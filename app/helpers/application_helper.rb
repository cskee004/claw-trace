# Extracted from cskee004/log-analyzer. This copy is now independent — changes here
# do not sync back to the original repository.

module ApplicationHelper
  # Formats a duration in milliseconds. Returns "—" if nil (no spans recorded).
  # Displays as "Xms" below 1000ms, or "X.Xs" at 1000ms and above.
  def format_duration(ms)
    return "—" if ms.nil?

    ms >= 1000 ? "#{(ms / 1000.0).round(1)}s" : "#{ms.round(1)}ms"
  end
end
