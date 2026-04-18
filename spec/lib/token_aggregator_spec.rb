require "rails_helper"

RSpec.describe TokenAggregator do
  def create_trace
    tid = SecureRandom.hex(8)
    Trace.create!(trace_id: tid, agent_id: "test-agent", task_name: "t", start_time: Time.current, status: "success")
    tid
  end

  def create_span(span_type:, input:, output:, cache_read:, cache_write:, total:)
    Span.create!(
      trace_id:                create_trace,
      span_id:                 SecureRandom.hex(8),
      span_type:               span_type,
      agent_id:                "test-agent",
      timestamp:               Time.current,
      span_input_tokens:       input,
      span_output_tokens:      output,
      span_cache_read_tokens:  cache_read,
      span_cache_write_tokens: cache_write,
      span_total_tokens:       total,
      metadata:                {}
    )
  end

  def create_model_span(input:, output:, cache_read:, cache_write:, total:)
    create_span(span_type: "model_call", input: input, output: output,
                cache_read: cache_read, cache_write: cache_write, total: total)
  end

  subject(:result) { TokenAggregator.call(Span.all) }

  describe "with model_call spans" do
    before do
      create_model_span(input: 100, output: 50, cache_read: 900, cache_write: 1000, total: 1050)
      create_model_span(input: 200, output: 80, cache_read: 1800, cache_write: 2000, total: 2080)
    end

    it "sums input_tokens" do
      expect(result[:input_tokens]).to eq(300)
    end

    it "sums output_tokens" do
      expect(result[:output_tokens]).to eq(130)
    end

    it "sums cache_read_tokens" do
      expect(result[:cache_read_tokens]).to eq(2700)
    end

    it "sums cache_write_tokens" do
      expect(result[:cache_write_tokens]).to eq(3000)
    end

    it "sums total_tokens" do
      expect(result[:total_tokens]).to eq(3130)
    end

    it "computes cache_hit_ratio as cache_read / (input + cache_read) * 100, rounded to 1dp" do
      # cache_read=2700, input=300 → 2700 / 3000 * 100 = 90.0
      expect(result[:cache_hit_ratio]).to eq(90.0)
    end
  end

  describe "with no spans" do
    it "returns zeros for all token counts" do
      expect(result[:input_tokens]).to eq(0)
      expect(result[:output_tokens]).to eq(0)
      expect(result[:cache_read_tokens]).to eq(0)
      expect(result[:cache_write_tokens]).to eq(0)
      expect(result[:total_tokens]).to eq(0)
    end

    it "returns nil cache_hit_ratio when there are no tokens" do
      expect(result[:cache_hit_ratio]).to be_nil
    end
  end

  describe "with spans that have nil token columns" do
    before do
      Span.create!(
        trace_id: create_trace, span_id: SecureRandom.hex(8),
        span_type: "model_call", agent_id: "a", timestamp: Time.current,
        metadata: {}
      )
    end

    it "treats nil columns as zero" do
      expect(result[:input_tokens]).to eq(0)
      expect(result[:total_tokens]).to eq(0)
    end
  end

  describe "includes agent_turn spans (plugin-emitted)" do
    before do
      create_model_span(input: 100, output: 50, cache_read: 0, cache_write: 0, total: 150)
      create_span(span_type: "agent_turn", input: 200, output: 80, cache_read: 0, cache_write: 0, total: 280)
    end

    it "sums tokens from both model_call and agent_turn spans" do
      expect(result[:input_tokens]).to eq(300)
      expect(result[:total_tokens]).to eq(430)
    end
  end

  describe "ignores non-LLM span types" do
    before do
      create_model_span(input: 100, output: 50, cache_read: 0, cache_write: 0, total: 150)
      Span.create!(
        trace_id: create_trace, span_id: SecureRandom.hex(8),
        span_type: "message_event", agent_id: "a", timestamp: Time.current,
        span_input_tokens: 9999, metadata: {}
      )
    end

    it "ignores message_event and other non-LLM spans" do
      expect(result[:input_tokens]).to eq(100)
    end
  end
end
