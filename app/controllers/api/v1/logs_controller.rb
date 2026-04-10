# frozen_string_literal: true

module Api
  module V1
    # Receives OTLP log payloads (ExportLogsServiceRequest).
    #
    # Accepts application/json only (protobuf support added in Task 38).
    # Unauthenticated by OTLP convention — no Bearer token required.
    # Always returns {} with HTTP 200 on success, per the OTLP spec.
    class LogsController < ActionController::API
      def create
        rows = LogsNormalizer.call(request.raw_post)
        Log.insert_all!(rows) if rows.any?
        render json: {}, status: :ok
      rescue LogsNormalizer::Error => e
        render json: { error: safe_message(e) }, status: :bad_request
      end

      private

      # Encodes error messages to UTF-8 to prevent JSON::GeneratorError when
      # the message contains binary characters (defensive: matches MetricsController).
      def safe_message(err)
        err.message.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
      end
    end
  end
end
