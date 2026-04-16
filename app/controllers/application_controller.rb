# Extracted from cskee004/log-analyzer. This copy is now independent — changes here
# do not sync back to the original repository.

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :set_status_bar

  private

  def set_status_bar
    last_log_at = Log.maximum(:timestamp)
    @status_bar = {
      last_log_at: last_log_at,
      live: last_log_at && last_log_at >= 2.minutes.ago
    }
  end
end
