require "rails_helper"

RSpec.describe TracesHelper, type: :helper do
  include TracesHelper
  # Lightweight stand-in for Span — only span_id and parent_span_id needed.
  SpanStub = Struct.new(:span_id, :parent_span_id)

  def stub(id, parent = nil)
    SpanStub.new(id, parent)
  end

  describe "#span_depth_map" do
    it "returns depth 0 for a single root span (no parent)" do
      result = span_depth_map([stub("root")])
      expect(result).to eq("root" => 0)
    end

    it "returns depth 1 for a direct child of the root" do
      spans = [stub("root"), stub("child", "root")]
      result = span_depth_map(spans)
      expect(result["root"]).to eq(0)
      expect(result["child"]).to eq(1)
    end

    it "returns depth 2 for a grandchild" do
      spans = [stub("root"), stub("child", "root"), stub("grandchild", "child")]
      result = span_depth_map(spans)
      expect(result["root"]).to eq(0)
      expect(result["child"]).to eq(1)
      expect(result["grandchild"]).to eq(2)
    end

    it "handles two independent root spans" do
      spans = [stub("r1"), stub("r2")]
      result = span_depth_map(spans)
      expect(result["r1"]).to eq(0)
      expect(result["r2"]).to eq(0)
    end

    it "treats an orphaned span (parent not in set) as depth 0" do
      spans = [stub("orphan", "missing-parent")]
      result = span_depth_map(spans)
      expect(result["orphan"]).to eq(0)
    end

    it "returns an empty hash for an empty span list" do
      expect(span_depth_map([])).to eq({})
    end
  end
end
