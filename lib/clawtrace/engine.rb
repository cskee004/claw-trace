module Clawtrace
  class Engine < ::Rails::Engine
    # Not isolated — controllers/models (TracesController, Trace, Span, ApiKey)
    # remain in the global namespace until a full namespace migration is done.
    #
    # To mount in a host app:
    #   # config/routes.rb
    #   mount Clawtrace::Engine, at: "/clawtrace"
  end
end
