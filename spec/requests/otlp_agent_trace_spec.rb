require "rails_helper"

# Validates the full pipeline for a realistic multi-turn agent trace:
#   POST /v1/traces → OtlpNormalizer → TelemetryIngester → DB
#
# Fixture layout (all times relative to base = 1776345852000ms):
#
#   openclaw.request   [==========================] 0ms → 5600ms (100%)
#     openclaw.agent.turn 1  [========]              0ms → 1940ms (34.6%)
#       openclaw.tool.exec            [====]       1940ms → 3200ms (22.5%)
#       openclaw.tool.read                 [==]    3200ms → 3800ms (10.7%)
#     openclaw.agent.turn 2                   [=====] 3800ms → 5600ms (32.1%)
#
# These are the values the waterfall timeline must reproduce exactly.

RSpec.describe "OTLP agent trace: POST /v1/traces → timeline", type: :request do
  AGENT_TRACE_ID = "a9f3e12b4c5d6e7f"

  BASE_MS = 1776345852000.0

  EXPECTED_DURATIONS_MS = {
    "a1b2c3d400000001" => 5600.0,  # openclaw.request
    "a1b2c3d400000002" => 1940.0,  # agent.turn 1
    "a1b2c3d400000003" => 1260.0,  # tool exec
    "a1b2c3d400000004" =>  600.0,  # tool read
    "a1b2c3d400000005" => 1800.0,  # agent.turn 2
  }.freeze

  EXPECTED_OFFSETS_MS = {
    "a1b2c3d400000001" =>    0.0,  # request at origin
    "a1b2c3d400000002" =>    0.0,  # turn 1 also starts at origin
    "a1b2c3d400000003" => 1940.0,  # exec starts when turn 1 ends
    "a1b2c3d400000004" => 3200.0,  # read starts when exec ends
    "a1b2c3d400000005" => 3800.0,  # turn 2 starts when read ends
  }.freeze

  let(:headers) { { "Content-Type" => "text/plain" }.freeze }

  before do
    post "/v1/traces", params: agent_trace_fixture_json, headers: headers
  end

  # ── Ingestion ──────────────────────────────────────────────────────────────

  describe "ingestion" do
    it "returns HTTP 200" do
      expect(response).to have_http_status(:ok)
    end

    it "creates one Trace" do
      expect(Trace.count).to eq(1)
    end

    it "creates five Spans" do
      expect(Span.count).to eq(5)
    end

    it "stores the correct trace_id" do
      expect(Trace.last.trace_id).to eq(AGENT_TRACE_ID)
    end

    it "stores agent_id from service.name fallback" do
      expect(Trace.last.agent_id).to eq("openclaw")
    end

    it "stores the correct span types" do
      types = Span.order(:timestamp).pluck(:span_type)
      expect(types).to eq(%w[agent_request agent_turn tool_call tool_call agent_turn])
    end

    it "stores end_time on every span" do
      expect(Span.where(end_time: nil).count).to eq(0)
    end
  end

  # ── Duration data ──────────────────────────────────────────────────────────

  describe "span durations" do
    it "each span duration matches expected value" do
      EXPECTED_DURATIONS_MS.each do |span_id, expected_ms|
        span = Span.find_by!(span_id: span_id)
        actual_ms = (span.end_time - span.timestamp) * 1000.0
        expect(actual_ms).to be_within(1).of(expected_ms),
          "#{span.span_name} (#{span_id}): expected #{expected_ms}ms, got #{actual_ms.round(1)}ms"
      end
    end
  end

  describe "total trace duration" do
    it "TraceDurationCalculator returns 5600ms" do
      trace = Trace.find_by!(trace_id: AGENT_TRACE_ID)
      trace.spans.load
      expect(TraceDurationCalculator.call(trace)).to be_within(1).of(5600.0)
    end
  end

  # ── Timeline offsets ───────────────────────────────────────────────────────

  describe "waterfall offsets" do
    it "each span offset from trace start matches expected value" do
      trace = Trace.find_by!(trace_id: AGENT_TRACE_ID)

      EXPECTED_OFFSETS_MS.each do |span_id, expected_offset_ms|
        span = Span.find_by!(span_id: span_id)
        actual_offset_ms = (span.timestamp - trace.start_time) * 1000.0
        expect(actual_offset_ms).to be_within(1).of(expected_offset_ms),
          "#{span.span_name} (#{span_id}): expected offset #{expected_offset_ms}ms, got #{actual_offset_ms.round(1)}ms"
      end
    end
  end

  # ── Waterfall percentages ──────────────────────────────────────────────────

  describe "waterfall bar percentages (total_ms = 5600)" do
    let(:total_ms) { 5600.0 }

    it "request bar is 100% wide" do
      span = Span.find_by!(span_id: "a1b2c3d400000001")
      width = (span.end_time - span.timestamp) * 1000.0 / total_ms * 100
      expect(width).to be_within(0.1).of(100.0)
    end

    it "turn 1 bar is 34.6% wide and starts at 0%" do
      span = Span.find_by!(span_id: "a1b2c3d400000002")
      trace = Trace.find_by!(trace_id: AGENT_TRACE_ID)
      width  = (span.end_time - span.timestamp) * 1000.0 / total_ms * 100
      offset = (span.timestamp - trace.start_time) * 1000.0 / total_ms * 100
      expect(width).to  be_within(0.1).of(34.64)
      expect(offset).to be_within(0.1).of(0.0)
    end

    it "exec bar starts where turn 1 ends (no gap)" do
      turn1 = Span.find_by!(span_id: "a1b2c3d400000002")
      exec  = Span.find_by!(span_id: "a1b2c3d400000003")
      expect(exec.timestamp).to eq(turn1.end_time)
    end

    it "read bar starts where exec ends (no gap)" do
      exec = Span.find_by!(span_id: "a1b2c3d400000003")
      read = Span.find_by!(span_id: "a1b2c3d400000004")
      expect(read.timestamp).to eq(exec.end_time)
    end

    it "turn 2 bar starts where read ends (no gap)" do
      read  = Span.find_by!(span_id: "a1b2c3d400000004")
      turn2 = Span.find_by!(span_id: "a1b2c3d400000005")
      expect(turn2.timestamp).to eq(read.end_time)
    end

    it "exec + read + turn2 widths sum to 65.4% (filling the rest after turn 1)" do
      trace = Trace.find_by!(trace_id: AGENT_TRACE_ID)
      spans = Span.where(span_id: %w[a1b2c3d400000003 a1b2c3d400000004 a1b2c3d400000005])
      total_width = spans.sum { |s| (s.end_time - s.timestamp) * 1000.0 / total_ms * 100 }
      expect(total_width).to be_within(0.1).of(65.36)
    end
  end

  # ── compute_latencies_ms (controller logic) ────────────────────────────────

  describe "compute_latencies_ms" do
    it "returns duration from end_time for every span that has one" do
      spans = Span.where(trace_id: AGENT_TRACE_ID).order(:timestamp).to_a
      ctrl  = TracesController.new
      latencies = ctrl.send(:compute_latencies_ms, spans)

      EXPECTED_DURATIONS_MS.each do |span_id, expected_ms|
        expect(latencies[span_id]).to be_within(1).of(expected_ms),
          "#{span_id}: expected #{expected_ms}ms, got #{latencies[span_id]&.round(1)}ms"
      end
    end
  end

  # ── Show page renders ─────────────────────────────────────────────────────

  describe "GET /traces/:trace_id" do
    it "returns 200 OK" do
      get "/traces/#{AGENT_TRACE_ID}"
      expect(response).to have_http_status(:ok)
    end

    it "renders the agent_request span type badge" do
      get "/traces/#{AGENT_TRACE_ID}"
      expect(response.body).to include("span-type-badge--agent_request")
    end

    it "renders the agent_turn span type badge" do
      get "/traces/#{AGENT_TRACE_ID}"
      expect(response.body).to include("span-type-badge--agent_turn")
    end

    it "renders the tool_call span type badge" do
      get "/traces/#{AGENT_TRACE_ID}"
      expect(response.body).to include("span-type-badge--tool_call")
    end
  end
end
