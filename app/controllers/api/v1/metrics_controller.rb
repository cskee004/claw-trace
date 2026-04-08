module Api
  module V1
    # Receives OTLP/JSON metrics payloads (ExportMetricsServiceRequest).
    #
    # Unauthenticated by OTLP convention — no Bearer token required.
    # Always returns {} with HTTP 200 on success, per the OTLP spec.
    class MetricsController < ActionController::API
      def create
        rows = MetricsNormalizer.call(request.raw_post)
        Metric.insert_all!(rows) if rows.any?
        render json: {}, status: :ok
      rescue MetricsNormalizer::Error => e
        render json: { error: e.message }, status: :bad_request
      end
    end
  end
end
