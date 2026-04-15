require "rails_helper"

RSpec.describe "GET /spans/:span_id/logs", type: :request do
  def create_log(span_id:, severity_text: "INFO", body: "a log message", offset_seconds: 0)
    Log.create!(
      span_id:         span_id,
      severity_text:   severity_text,
      severity_number: 9,
      body:            body,
      log_attributes:  {},
      timestamp:       Time.utc(2026, 4, 14, 10, 0, offset_seconds)
    )
  end

  describe "span with matching logs" do
    before do
      create_log(span_id: "abc123", severity_text: "INFO",  body: "started", offset_seconds: 0)
      create_log(span_id: "abc123", severity_text: "ERROR", body: "failed",  offset_seconds: 1)
    end

    it "returns 200" do
      get "/spans/abc123/logs"
      expect(response).to have_http_status(:ok)
    end

    it "renders log body text" do
      get "/spans/abc123/logs"
      expect(response.body).to include("started")
      expect(response.body).to include("failed")
    end

    it "renders severity labels" do
      get "/spans/abc123/logs"
      expect(response.body).to include("severity-badge--info")
      expect(response.body).to include("severity-badge--error")
    end

    it "renders FATAL severity label" do
      create_log(span_id: "abc123", severity_text: "FATAL", body: "process crashed", offset_seconds: 2)
      get "/spans/abc123/logs"
      expect(response.body).to include("severity-badge--error")
    end
  end

  describe "span with no logs" do
    it "returns 200" do
      get "/spans/no-such-span/logs"
      expect(response).to have_http_status(:ok)
    end

    it "renders no log content" do
      get "/spans/no-such-span/logs"
      expect(response.body).not_to include("[INFO]")
      expect(response.body).not_to include("[ERROR]")
    end
  end
end
