require "rails_helper"

RSpec.describe DashboardController, type: :controller do
  describe "#show_plugin_banner?" do
    def create_trace(trace_id:, span_count: 1)
      trace = Trace.create!(
        trace_id:   trace_id,
        agent_id:   "agent-1",
        task_name:  "test",
        start_time: 1.hour.ago,
        status:     :success
      )
      span_count.times do |i|
        Span.create!(
          trace_id:  trace.trace_id,
          span_id:   "#{trace_id}-s#{i}",
          span_type: "model_call",
          timestamp: 1.hour.ago,
          agent_id:  "agent-1",
          metadata:  {}
        )
      end
      trace
    end

    it "returns false when there are no recent traces" do
      expect(controller.send(:show_plugin_banner?)).to be false
    end

    it "returns false when ≤90% of recent traces are single-span" do
      # 1 single-span, 1 multi-span → 50% single-span ratio
      create_trace(trace_id: "aaa1111111111111", span_count: 1)
      create_trace(trace_id: "bbb2222222222222", span_count: 3)
      expect(controller.send(:show_plugin_banner?)).to be false
    end

    it "returns true when >90% of recent traces are single-span" do
      # 10 single-span, 0 multi-span → 100% single-span ratio
      # (The zero-multi-span path collapses into the >90% case)
      10.times do |i|
        create_trace(trace_id: "aaa#{i.to_s.rjust(13, '0')}", span_count: 1)
      end
      expect(controller.send(:show_plugin_banner?)).to be true
    end
  end
end
