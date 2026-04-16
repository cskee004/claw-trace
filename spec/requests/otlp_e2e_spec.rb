require "rails_helper"

# Phase 3: e2e specs rebuilt on real OpenClaw fixtures.
# Failures on span_type, agent_id, and first-class column assertions are
# intentional — they define the Phase 4 implementation contract.

RSpec.describe "OTLP end-to-end: POST /v1/traces → DB → UI", type: :request do
  let(:headers) { { "Content-Type" => "text/plain" }.freeze }

  # ── Model usage fixture ───────────────────────────────────────────────────────

  describe "model usage fixture (openclaw.model.usage)" do
    MODEL_TRACE_ID = "3814946c5476f418"

    before { post "/v1/traces", params: model_usage_fixture_json, headers: headers }

    describe "HTTP response" do
      it "returns 200 OK" do
        expect(response).to have_http_status(:ok)
      end

      it "returns an empty JSON object" do
        expect(JSON.parse(response.body)).to eq({})
      end
    end

    describe "DB persistence" do
      it "creates exactly one Trace" do
        expect(Trace.count).to eq(1)
      end

      it "creates exactly one Span (flat single-span trace)" do
        expect(Span.count).to eq(1)
      end

      it "stores the correct trace_id" do
        expect(Trace.last.trace_id).to eq(MODEL_TRACE_ID)
      end

      it "stores agent_id from openclaw.sessionKey span attribute" do
        expect(Trace.last.agent_id).to eq("agent:main:discord:channel:1494326249361899544")
      end

      it "stores task_name as the OTLP span name" do
        expect(Trace.last.task_name).to eq("openclaw.model.usage")
      end

      it "stores status as success" do
        expect(Trace.last.status).to eq("success")
      end

      it "stores span_type as model_call" do
        expect(Span.last.span_type).to eq("model_call")
      end

      it "stores span_name as openclaw.model.usage" do
        expect(Span.last.span_name).to eq("openclaw.model.usage")
      end

      it "stores parent_span_id as nil (root span)" do
        expect(Span.last.parent_span_id).to be_nil
      end

      it "stores end_time (endTimeUnixNano present in fixture)" do
        expect(Span.last.end_time).not_to be_nil
      end

      # First-class columns — RED until Phase 4 migration
      it "stores span_model" do
        expect(Span.last.span_model).to eq("claude-haiku-4-5-20251001")
      end

      it "stores span_provider" do
        expect(Span.last.span_provider).to eq("anthropic")
      end

      it "stores span_input_tokens" do
        expect(Span.last.span_input_tokens).to eq(2)
      end

      it "stores span_output_tokens" do
        expect(Span.last.span_output_tokens).to eq(246)
      end

      it "stores span_cache_read_tokens" do
        expect(Span.last.span_cache_read_tokens).to eq(94270)
      end

      it "stores span_cache_write_tokens" do
        expect(Span.last.span_cache_write_tokens).to eq(94649)
      end

      it "stores span_total_tokens" do
        expect(Span.last.span_total_tokens).to eq(94714)
      end

      it "stores span_outcome as nil" do
        expect(Span.last.span_outcome).to be_nil
      end
    end

    describe "GET /traces (trace list)" do
      it "returns 200 OK" do
        get "/traces"
        expect(response).to have_http_status(:ok)
      end

      it "renders the trace_id" do
        get "/traces"
        expect(response.body).to include(MODEL_TRACE_ID)
      end

      it "renders the agent_id" do
        get "/traces"
        expect(response.body).to include("agent:main:discord:channel:1494326249361899544")
      end

      it "renders the success status badge" do
        get "/traces"
        expect(response.body).to include("status-badge--success")
      end
    end

    describe "GET /traces/:trace_id (show)" do
      it "returns 200 OK" do
        get "/traces/#{MODEL_TRACE_ID}"
        expect(response).to have_http_status(:ok)
      end

      it "renders the trace_id" do
        get "/traces/#{MODEL_TRACE_ID}"
        expect(response.body).to include(MODEL_TRACE_ID)
      end

      it "renders the model_call span type badge" do
        get "/traces/#{MODEL_TRACE_ID}"
        expect(response.body).to include("span-type-badge--model_call")
      end
    end
  end

  # ── Message processed fixture ─────────────────────────────────────────────────

  describe "message processed fixture (openclaw.message.processed)" do
    MESSAGE_TRACE_ID = "ea38f13d10ee6301"

    before { post "/v1/traces", params: message_processed_fixture_json, headers: headers }

    describe "HTTP response" do
      it "returns 200 OK" do
        expect(response).to have_http_status(:ok)
      end
    end

    describe "DB persistence" do
      it "creates exactly one Trace" do
        expect(Trace.count).to eq(1)
      end

      it "creates exactly one Span" do
        expect(Span.count).to eq(1)
      end

      it "stores the correct trace_id" do
        expect(Trace.last.trace_id).to eq(MESSAGE_TRACE_ID)
      end

      it "stores agent_id from openclaw.sessionKey span attribute" do
        expect(Trace.last.agent_id).to eq("agent:main:discord:channel:1494326249361899544")
      end

      it "stores span_type as message_event" do
        expect(Span.last.span_type).to eq("message_event")
      end

      it "stores span_outcome as completed" do
        expect(Span.last.span_outcome).to eq("completed")
      end

      it "stores span_model as nil" do
        expect(Span.last.span_model).to be_nil
      end

      it "stores span_input_tokens as nil" do
        expect(Span.last.span_input_tokens).to be_nil
      end
    end

    describe "GET /traces (trace list)" do
      it "returns 200 OK" do
        get "/traces"
        expect(response).to have_http_status(:ok)
      end

      it "renders the trace_id" do
        get "/traces"
        expect(response.body).to include(MESSAGE_TRACE_ID)
      end
    end

    describe "GET /traces/:trace_id (show)" do
      it "returns 200 OK" do
        get "/traces/#{MESSAGE_TRACE_ID}"
        expect(response).to have_http_status(:ok)
      end

      it "renders the message_event span type badge" do
        get "/traces/#{MESSAGE_TRACE_ID}"
        expect(response.body).to include("span-type-badge--message_event")
      end
    end
  end
end
