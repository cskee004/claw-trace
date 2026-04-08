# frozen_string_literal: true

module Api
  module V1
    # Receives OTLP trace payloads from OpenClaw (or any OTLP-compatible sender).
    #
    # Accepts both application/json and application/x-protobuf.
    # Unauthenticated by OTLP convention — no Bearer token required.
    # Always returns {} with HTTP 200 on success, per the OTLP spec.
    class OtlpController < ActionController::API
      def create
        if request.content_type == "application/x-protobuf"
          data = OtlpProtobufDecoder.decode_traces(request.raw_post)
          return render json: {}, status: :ok if data["resourceSpans"].blank?

          result = OtlpNormalizer.call(data.to_json)
        else
          body = request.raw_post
          data = JSON.parse(body)
          return render json: {}, status: :ok if data["resourceSpans"].blank?

          result = OtlpNormalizer.call(body)
        end

        TelemetryIngester.call(**result)
        render json: {}, status: :ok
      rescue JSON::ParserError => e
        render json: { error: "invalid JSON: #{e.message}" }, status: :bad_request
      rescue OtlpProtobufDecoder::Error => e
        render json: { error: e.message }, status: :bad_request
      rescue OtlpNormalizer::Error, TelemetryIngester::Error => e
        render json: { error: e.message }, status: :bad_request
      end
    end
  end
end
