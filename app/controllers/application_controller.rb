# Extracted from cskee004/log-analyzer. This copy is now independent — changes here
# do not sync back to the original repository.

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :set_status_bar

  private

  def set_status_bar
    last_metric_at = Metric.maximum(:updated_at)
    @status_bar = {
      last_activity_at: last_metric_at,
      live: last_metric_at && last_metric_at >= 5.minutes.ago
    }
  end
end
