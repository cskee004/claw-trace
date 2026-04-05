require "rails_helper"
require_relative "../../simulator/agent_simulator"

RSpec.describe "OTLP end-to-end: simulator → POST /v1/traces → DB → UI", type: :request do
  E2E_HEADERS = { "Content-Type" => "text/plain" }.freeze

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

  E2E_SPAN_TYPE_TO_OTLP_NAME = {
    "agent_run_started" => "openclaw.request",
    "model_call"        => "openclaw.agent.turn",
    "model_response"    => "openclaw.agent.turn",
    "tool_call"         => "tool.use",
    "tool_result"       => "tool.use",
    "decision"          => "openclaw.command.decide",
    # run_completed: normalizer promotes the final span via max startTimeUnixNano
    "run_completed"     => "openclaw.agent.turn"
  }.freeze

  # ── Conversion helpers ────────────────────────────────────────────────────

  def event_to_otlp_span(event, index: 0)
    t    = Time.parse(event.timestamp)
    # SpanGenerator uses iso8601 without sub-second precision, so multiple spans
    # can share the same second timestamp. Add index milliseconds so nanosecond
    # ordering matches the simulator sequence, ensuring the normalizer's
    # final-span detection (max startTimeUnixNano) tags s7 as run_completed.
    nano = (t.to_r * 1_000_000_000).to_i + (index * 1_000_000)

    span = {
      "traceId"           => "#{event.trace_id}#{"0" * 16}",
      "spanId"            => event.span_id,
      "name"              => E2E_SPAN_TYPE_TO_OTLP_NAME.fetch(event.span_type, "openclaw.agent.turn"),
      "startTimeUnixNano" => nano.to_s,
      "attributes"        => (event.metadata || {}).map { |k, v|
        attr_value = case v
                     when Integer          then { "intValue" => v }
                     when Float            then { "doubleValue" => v }
                     when TrueClass, FalseClass then { "boolValue" => v }
                     else { "stringValue" => v.to_s }
                     end
        { "key" => k.to_s, "value" => attr_value }
      }
    }
    span["parentSpanId"] = event.parent_span_id if event.parent_span_id
    span["status"] = { "code" => 2 } if event.span_type == "error"
    span
  end

  def build_otlp_payload(sim_run)
    JSON.generate({
      "resourceSpans" => [{
        "resource" => {
          "attributes" => [
            { "key" => "openclaw.session.key",
              "value" => { "stringValue" => sim_run.trace.agent_id } }
          ]
        },
        "scopeSpans" => [{ "spans" => sim_run.spans.each_with_index.map { |e, i| event_to_otlp_span(e, index: i) } }]
      }]
    })
  end

  # ── Simulator setup ───────────────────────────────────────────────────────

  let(:sim_run) do
    AgentSimulator.new(seed: 42, failure_rate: 0).run(
      agent_id:   "support-agent",
      start_time: Time.utc(2026, 1, 1, 12, 0, 0)
    )
  end
  let(:trace_id) { sim_run.trace.trace_id }
  let(:payload)  { build_otlp_payload(sim_run) }

  def post_trace
    post "/v1/traces", params: payload, headers: E2E_HEADERS
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
      expect(Trace.last.trace_id).to eq(trace_id)
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
      stored = Span.where(trace_id: trace_id).order(:timestamp).pluck(:span_type)
      expect(stored).to eq(E2E_EXPECTED_SPAN_TYPES)
    end

    it "stores the root span (s1) with nil parent_span_id" do
      root = Span.where(trace_id: trace_id).order(:timestamp).first
      expect(root.parent_span_id).to be_nil
    end

    it "stores s2 parented to s1 (model_call child of agent_run_started)" do
      ordered = Span.where(trace_id: trace_id).order(:timestamp).to_a
      expect(ordered[1].parent_span_id).to eq(ordered[0].span_id)
    end

    it "stores a non-nil metadata Hash for every span" do
      Span.where(trace_id: trace_id).each do |span|
        expect(span.metadata).to be_a(Hash)
      end
    end

    it "stores non-empty metadata for the agent_run_started span" do
      root_span = Span.where(trace_id: trace_id).order(:timestamp).first
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
      expect(response.body).to include(trace_id)
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
      get "/traces/#{trace_id}"
      expect(response).to have_http_status(:ok)
    end

    it "renders the trace_id in the metadata section" do
      get "/traces/#{trace_id}"
      expect(response.body).to include(trace_id)
    end

    it "renders the agent_id" do
      get "/traces/#{trace_id}"
      expect(response.body).to include("support-agent")
    end

    it "renders the success status badge" do
      get "/traces/#{trace_id}"
      expect(response.body).to include("status-badge--success")
    end

    it "renders the agent_run_started span type badge" do
      get "/traces/#{trace_id}"
      expect(response.body).to include("span-type-badge--agent_run_started")
    end

    it "renders the decision span type badge" do
      get "/traces/#{trace_id}"
      expect(response.body).to include("span-type-badge--decision")
    end

    it "renders the run_completed span type badge" do
      get "/traces/#{trace_id}"
      expect(response.body).to include("span-type-badge--run_completed")
    end

    it "renders the span count (7) in the metadata section" do
      get "/traces/#{trace_id}"
      expect(response.body).to include(">7<")
    end
  end
end
