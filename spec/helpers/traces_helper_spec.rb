require "rails_helper"

RSpec.describe TracesHelper, type: :helper do
  include TracesHelper

  # Lightweight stand-in for Span — needs span_id, parent_span_id, and timestamp.
  SpanStub = Struct.new(:span_id, :parent_span_id, :timestamp)

  def stub(id, parent = nil, ts = Time.at(0))
    SpanStub.new(id, parent, ts)
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

  describe "#dfs_ordered_spans" do
    let(:t0) { Time.at(0) }
    let(:t1) { Time.at(1) }
    let(:t2) { Time.at(2) }
    let(:t3) { Time.at(3) }
    let(:t4) { Time.at(4) }

    it "returns an empty array for empty input" do
      expect(dfs_ordered_spans([])).to eq([])
    end

    it "returns a single root span unchanged" do
      root = stub("root", nil, t0)
      expect(dfs_ordered_spans([root])).to eq([root])
    end

    it "places a child immediately after its parent" do
      root  = stub("root",  nil,    t0)
      child = stub("child", "root", t1)
      result = dfs_ordered_spans([root, child])
      expect(result).to eq([root, child])
    end

    it "places grandchild after child, not after root" do
      root       = stub("root",       nil,     t0)
      child      = stub("child",      "root",  t1)
      grandchild = stub("grandchild", "child", t2)
      # Input deliberately out of DFS order
      result = dfs_ordered_spans([root, grandchild, child])
      expect(result).to eq([root, child, grandchild])
    end

    it "sorts sibling children by timestamp within the same parent" do
      root   = stub("root",   nil,    t0)
      child1 = stub("c1",     "root", t2)  # later timestamp
      child2 = stub("c2",     "root", t1)  # earlier timestamp
      result = dfs_ordered_spans([root, child1, child2])
      expect(result).to eq([root, child2, child1])
    end

    it "fully exhausts one subtree before visiting sibling subtree" do
      # root → [a, b]; a → [a1]; b → [b1]
      # DFS pre-order: root, a, a1, b, b1
      root = stub("root", nil,    t0)
      a    = stub("a",    "root", t1)
      b    = stub("b",    "root", t3)
      a1   = stub("a1",   "a",    t2)
      b1   = stub("b1",   "b",    t4)
      result = dfs_ordered_spans([root, b, a1, a, b1])
      expect(result).to eq([root, a, a1, b, b1])
    end

    it "handles an orphaned span (parent missing from set) as a root" do
      orphan = stub("orphan", "missing", t0)
      result = dfs_ordered_spans([orphan])
      expect(result).to eq([orphan])
    end

    it "handles multiple root spans sorted by timestamp" do
      r1 = stub("r1", nil, t2)
      r2 = stub("r2", nil, t0)
      result = dfs_ordered_spans([r1, r2])
      expect(result).to eq([r2, r1])
    end

    it "places a root span first even when timestamp-sorted input would put it mid-list" do
      # Scenario 5 regression: root arrives with a later timestamp than some children
      root  = stub("root",  nil,    t3)  # root has LATEST timestamp
      child = stub("child", "root", t0)  # child has earliest timestamp
      grand = stub("grand", "child", t1)
      # Timestamp order would be: child(t0), grand(t1), root(t3)
      # DFS pre-order must be:    root, child, grand
      result = dfs_ordered_spans([child, grand, root])
      expect(result).to eq([root, child, grand])
    end
  end
end
