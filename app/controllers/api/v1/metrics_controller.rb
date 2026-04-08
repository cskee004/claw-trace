# frozen_string_literal: true

module Api
  module V1
    # Receives OTLP metrics payloads (ExportMetricsServiceRequest).
    #
    # Accepts both application/json and application/x-protobuf.
    # Unauthenticated by OTLP convention — no Bearer token required.
    # Always returns {} with HTTP 200 on success, per the OTLP spec.
    class MetricsController < ActionController::API
      def create
        body = if request.content_type == "application/x-protobuf"
          OtlpProtobufDecoder.decode_metrics(request.raw_post).to_json
        else
          request.raw_post
        end

        rows = MetricsNormalizer.call(body)
        Metric.insert_all!(rows) if rows.any?
        render json: {}, status: :ok
      rescue OtlpProtobufDecoder::Error => e
        render json: { error: safe_message(e) }, status: :bad_request
      rescue MetricsNormalizer::Error => e
        render json: { error: safe_message(e) }, status: :bad_request
      end

      private

      # Encodes error messages to UTF-8 to prevent JSON::GeneratorError when
      # the message contains binary characters from a malformed protobuf input.
      def safe_message(err)
        err.message.encode("UTF-8", invalid: :replace, undef: :replace, replace: "?")
      end
    end
  end
end
