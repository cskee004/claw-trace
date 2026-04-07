module Api
  module V1
    # Receives OTLP/JSON trace payloads from OpenClaw (or any OTLP-compatible sender).
    #
    # Unauthenticated by OTLP convention — no Bearer token required.
    # Always returns {} with HTTP 200 on success, per the OTLP spec.
    class OtlpController < ActionController::API
      def create
        body = request.raw_post
        data = JSON.parse(body)

        return render json: {}, status: :ok if data["resourceSpans"].blank?

        result = OtlpNormalizer.call(body)
        TelemetryIngester.call(**result)
        render json: {}, status: :ok
      rescue JSON::ParserError => e
        render json: { error: "invalid JSON: #{e.message}" }, status: :bad_request
      rescue OtlpNormalizer::Error, TelemetryIngester::Error => e
        render json: { error: e.message }, status: :bad_request
      end
    end
  end
end
