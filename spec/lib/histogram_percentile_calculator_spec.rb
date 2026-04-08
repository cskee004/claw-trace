require "rails_helper"

RSpec.describe HistogramPercentileCalculator do
  # Buckets:  [0-100]: 10, [100-300]: 40, [300-500]: 60, [500-700]: 30, [700-1400]: 10
  # Total: 150
  let(:bucket_counts)   { [10, 40, 60, 30, 10] }
  let(:explicit_bounds) { [100.0, 300.0, 500.0, 700.0] }

  subject(:result) { described_class.call(bucket_counts: bucket_counts, explicit_bounds: explicit_bounds) }

  it "returns a hash with :p50, :p95, :p99 keys" do
    expect(result.keys).to contain_exactly(:p50, :p95, :p99)
  end

  it "computes p50 ≈ 383.3 (interpolated in 300–500 bucket)" do
    # target=75; cumulative: 10, 50, 110 → bucket 2 [300,500], fraction=(75-50)/60=0.4167
    expect(result[:p50]).to be_within(1.0).of(383.33)
  end

  it "computes p95 ≈ 875.0 (interpolated in last bucket with estimated upper=1400)" do
    # target=142.5; cumulative: 10,50,110,140,150 → bucket 4 [700,1400], fraction=(142.5-140)/10=0.25
    expect(result[:p95]).to be_within(1.0).of(875.0)
  end

  it "computes p99 ≈ 1295.0 (high in last bucket)" do
    # target=148.5; fraction=(148.5-140)/10=0.85; 700+700*0.85=1295
    expect(result[:p99]).to be_within(1.0).of(1295.0)
  end

  it "returns nil for empty bucket_counts" do
    expect(described_class.call(bucket_counts: [], explicit_bounds: [])).to be_nil
  end

  it "returns nil when all counts are zero" do
    expect(described_class.call(bucket_counts: [0, 0, 0], explicit_bounds: [10.0, 20.0])).to be_nil
  end

  it "handles a single-bucket histogram (no explicit_bounds)" do
    result = described_class.call(bucket_counts: [5], explicit_bounds: [])
    expect(result[:p50]).to eq(0.0)  # lower=0, upper=0 (no bounds), single bucket
  end
end
