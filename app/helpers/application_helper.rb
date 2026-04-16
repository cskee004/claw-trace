# Extracted from cskee004/log-analyzer. This copy is now independent — changes here
# do not sync back to the original repository.

module ApplicationHelper
  APP_VERSION = "0.1.0"

  # Formats a duration in milliseconds. Returns "—" if nil (no spans recorded).
  # Displays as "Xms" below 1000ms, or "X.Xs" at 1000ms and above.
  def format_duration(ms)
    return "—" if ms.nil?

    ms >= 1000 ? "#{(ms / 1000.0).round(1)}s" : "#{ms.round(1)}ms"
  end

  # Returns a human-readable relative label for +time+ relative to +now+.
  # Examples: "just now", "5 min ago", "2 hr ago", "Yesterday", "Sat 11", "Apr 4", "Nov 3, 2024"
  # Future timestamps (negative diff) fall through to "just now" — intentional for OTLP clock skew.
  def format_time_relative(time, now: Time.current)
    diff = now - time

    return "just now"                      if diff < 60
    # date guard prevents "5 min ago" for a span from 23:58 yesterday when now is 00:03 today
    return "#{(diff / 60).to_i} min ago"   if diff < 3600 && time.to_date == now.to_date
    return "#{(diff / 3600).to_i} hr ago"  if diff < 86_400 && time.to_date == now.to_date

    return "Yesterday" if time.to_date == now.to_date - 1

    if diff < 7 * 86_400
      return "#{time.strftime('%a')} #{time.day}"
    end

    if time.year == now.year
      return "#{time.strftime('%b')} #{time.day}"
    end

    "#{time.strftime('%b')} #{time.day}, #{time.year}"
  end

  # Returns the UTC wall-clock time as "HH:MM:SS".
  def format_time_absolute(time)
    time.utc.strftime("%H:%M:%S")
  end

  # Returns the CSS modifier class for a severity badge element.
  # Shared by the logs index table and the span drawer partial.
  def severity_badge_class(severity_text)
    case severity_text&.upcase
    when "ERROR", "FATAL" then "severity-badge--error"
    when "WARN"           then "severity-badge--warn"
    when "INFO"           then "severity-badge--info"
    when "DEBUG"          then "severity-badge--debug"
    else                       "severity-badge--info"
    end
  end
end
