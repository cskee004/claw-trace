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

          json_body = data.to_json
          OtlpPayloadDumper.dump(:traces, json_body)
          results = OtlpNormalizer.call(json_body)
        else
          body = request.raw_post
          data = JSON.parse(body)
          return render json: {}, status: :ok if data["resourceSpans"].blank?

          OtlpPayloadDumper.dump(:traces, body)
          results = OtlpNormalizer.call(body)
        end

        ActiveRecord::Base.transaction do
          results.each { |r| TelemetryIngester.call(**r) }
        end
        render json: {}, status: :ok
      rescue OtlpProtobufDecoder::Error => e
        render json: { error: safe_message(e) }, status: :bad_request
      rescue JSON::ParserError => e
        render json: { error: "invalid JSON: #{safe_message(e)}" }, status: :bad_request
      rescue OtlpNormalizer::Error, TelemetryIngester::Error => e
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
