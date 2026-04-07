require "rails_helper"

RSpec.describe "OTLP end-to-end: POST /v1/traces → DB → UI", type: :request do
  E2E_HEADERS = { "Content-Type" => "text/plain" }.freeze

  TRACE_ID    = "a1b2c3d4e5f6a7b8"
  TRACE_ID_32 = "#{TRACE_ID}#{"0" * 16}"

  # Post-normalization span types the DB will contain after the round-trip.
  # model_response and tool_result have no distinct OTLP names, so they come
  # back as model_call and tool_call respectively (expected lossy mapping).
  E2E_EXPECTED_SPAN_TYPES = %w[
    agent_run_started
    model_call
    model_call
    tool_call
    tool_call
    decision
    run_completed
  ].freeze

  # Static 7-span OTLP payload. Timestamps are strictly increasing (1ms apart)
  # so OtlpNormalizer's final-span detection (max startTimeUnixNano) reliably
  # promotes s7 to run_completed. s1 carries a metadata attribute to satisfy
  # the "non-empty metadata for agent_run_started" assertion.
  E2E_PAYLOAD = JSON.generate({
    "resourceSpans" => [{
      "resource" => {
        "attributes" => [
          { "key" => "openclaw.session.key", "value" => { "stringValue" => "support-agent" } }
        ]
      },
      "scopeSpans" => [{
        "spans" => [
          {
            "traceId"           => TRACE_ID_32,
            "spanId"            => "s1",
            "name"              => "openclaw.request",
            "startTimeUnixNano" => "1000000000000000000",
            "attributes"        => [{ "key" => "task", "value" => { "stringValue" => "classify_customer_ticket" } }]
          },
          {
            "traceId"           => TRACE_ID_32,
            "spanId"            => "s2",
            "parentSpanId"      => "s1",
            "name"              => "openclaw.agent.turn",
            "startTimeUnixNano" => "1000001000000000000",
            "attributes"        => []
          },
          {
            "traceId"           => TRACE_ID_32,
            "spanId"            => "s3",
            "parentSpanId"      => "s2",
            "name"              => "openclaw.agent.turn",
            "startTimeUnixNano" => "1000002000000000000",
            "attributes"        => []
          },
          {
            "traceId"           => TRACE_ID_32,
            "spanId"            => "s4",
            "parentSpanId"      => "s2",
            "name"              => "tool.use",
            "startTimeUnixNano" => "1000003000000000000",
            "attributes"        => []
          },
          {
            "traceId"           => TRACE_ID_32,
            "spanId"            => "s5",
            "parentSpanId"      => "s2",
            "name"              => "tool.use",
            "startTimeUnixNano" => "1000004000000000000",
            "attributes"        => []
          },
          {
            "traceId"           => TRACE_ID_32,
            "spanId"            => "s6",
            "parentSpanId"      => "s1",
            "name"              => "openclaw.command.decide",
            "startTimeUnixNano" => "1000005000000000000",
            "attributes"        => []
          },
          {
            "traceId"           => TRACE_ID_32,
            "spanId"            => "s7",
            "parentSpanId"      => "s1",
            "name"              => "openclaw.agent.turn",
            "startTimeUnixNano" => "1000006000000000000",
            "attributes"        => []
          }
        ]
      }]
    }]
  }).freeze

  def post_trace
    post "/v1/traces", params: E2E_PAYLOAD, headers: E2E_HEADERS
  end

  # ── HTTP response ─────────────────────────────────────────────────────────

  describe "HTTP response" do
    it "returns 200 OK" do
      post_trace
      expect(response).to have_http_status(:ok)
    end

    it "returns an empty JSON object body" do
      post_trace
      expect(JSON.parse(response.body)).to eq({})
    end
  end

  # ── DB persistence ────────────────────────────────────────────────────────

  describe "DB persistence" do
    before { post_trace }

    it "creates exactly one Trace record" do
      expect(Trace.count).to eq(1)
    end

    it "creates exactly 7 Span records" do
      expect(Span.count).to eq(7)
    end

    it "stores the correct trace_id (simulator trace_id = first 16 chars of padded OTLP traceId)" do
      expect(Trace.last.trace_id).to eq(TRACE_ID)
    end

    it "stores the correct agent_id" do
      expect(Trace.last.agent_id).to eq("support-agent")
    end

    it "stores task_name as the OTLP root span name, not the simulator task string" do
      expect(Trace.last.task_name).to eq("openclaw.request")
    end

    it "stores status as success (failure_rate: 0 guarantees no error injection)" do
      expect(Trace.last.status).to eq("success")
    end

    it "stores a parseable start_time" do
      expect(Trace.last.start_time).to be_a(Time)
    end

    it "persists span_types in post-normalization order (sorted by timestamp)" do
      stored = Span.where(trace_id: TRACE_ID).order(:timestamp).pluck(:span_type)
      expect(stored).to eq(E2E_EXPECTED_SPAN_TYPES)
    end

    it "stores the root span (s1) with nil parent_span_id" do
      root = Span.where(trace_id: TRACE_ID).order(:timestamp).first
      expect(root.parent_span_id).to be_nil
    end

    it "stores s2 parented to s1 (model_call child of agent_run_started)" do
      ordered = Span.where(trace_id: TRACE_ID).order(:timestamp).to_a
      expect(ordered[1].parent_span_id).to eq(ordered[0].span_id)
    end

    it "stores a non-nil metadata Hash for every span" do
      Span.where(trace_id: TRACE_ID).each do |span|
        expect(span.metadata).to be_a(Hash)
      end
    end

    it "stores non-empty metadata for the agent_run_started span" do
      root_span = Span.where(trace_id: TRACE_ID).order(:timestamp).first
      expect(root_span.span_type).to eq("agent_run_started")
      expect(root_span.metadata).not_to be_empty
    end
  end

  # ── Trace list view ───────────────────────────────────────────────────────

  describe "GET /traces (trace list)" do
    before { post_trace }

    it "returns 200 OK" do
      get "/traces"
      expect(response).to have_http_status(:ok)
    end

    it "renders the trace_id as a link" do
      get "/traces"
      expect(response.body).to include(TRACE_ID)
    end

    it "renders the agent_id" do
      get "/traces"
      expect(response.body).to include("support-agent")
    end

    it "renders the success status badge" do
      get "/traces"
      expect(response.body).to include("status-badge--success")
    end

    it "renders the task_name (OTLP root span name)" do
      get "/traces"
      expect(response.body).to include("openclaw.request")
    end
  end

  # ── Timeline view ─────────────────────────────────────────────────────────

  describe "GET /traces/:trace_id (timeline)" do
    before { post_trace }

    it "returns 200 OK" do
      get "/traces/#{TRACE_ID}"
      expect(response).to have_http_status(:ok)
    end

    it "renders the trace_id in the metadata section" do
      get "/traces/#{TRACE_ID}"
      expect(response.body).to include(TRACE_ID)
    end

    it "renders the agent_id" do
      get "/traces/#{TRACE_ID}"
      expect(response.body).to include("support-agent")
    end

    it "renders the success status badge" do
      get "/traces/#{TRACE_ID}"
      expect(response.body).to include("status-badge--success")
    end

    it "renders the agent_run_started span type badge" do
      get "/traces/#{TRACE_ID}"
      expect(response.body).to include("span-type-badge--agent_run_started")
    end

    it "renders the decision span type badge" do
      get "/traces/#{TRACE_ID}"
      expect(response.body).to include("span-type-badge--decision")
    end

    it "renders the run_completed span type badge" do
      get "/traces/#{TRACE_ID}"
      expect(response.body).to include("span-type-badge--run_completed")
    end

    it "renders the span count (7) in the metadata section" do
      get "/traces/#{TRACE_ID}"
      expect(response.body).to include(">7<")
    end
  end
end
