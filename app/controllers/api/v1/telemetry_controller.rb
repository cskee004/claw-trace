module Api
  module V1
    class TelemetryController < Api::V1::BaseController
      def create
        lines = request.raw_post.split("\n").map(&:strip).reject(&:empty?)
        trace_data, *span_data = lines.map { |l| JSON.parse(l) }
        result = TelemetryIngester.call(trace: trace_data, spans: span_data)
        render json: result, status: :created
      rescue JSON::ParserError => e
        render json: { error: "invalid JSON: #{e.message}" }, status: :unprocessable_content
      rescue TelemetryIngester::Error => e
        render json: { error: e.message }, status: :unprocessable_content
      end
    end
  end
end
