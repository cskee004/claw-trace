require "rails_helper"

RSpec.describe ModelPricingService do
  let(:service) { described_class.new }

  let(:catalog) do
    {
      "claude-haiku-4-5-20251001" => { "input_cost_per_token" => 0.0000008, "output_cost_per_token" => 0.000004 },
      "claude-sonnet-4-6"         => { "input_cost_per_token" => 0.000003,  "output_cost_per_token" => 0.000015 },
      "claude-sonnet"             => { "input_cost_per_token" => 0.000003,  "output_cost_per_token" => 0.000015 },
      "gpt-4o"                    => { "input_cost_per_token" => 0.0000025, "output_cost_per_token" => 0.00001  }
    }
  end

  before do
    Rails.cache.clear
    allow(service).to receive(:fetch_remote).and_return(catalog)
  end

  describe "#cost_usd" do
    it "returns cost for an exact model match" do
      cost = service.cost_usd(model: "gpt-4o", input_tokens: 1000, output_tokens: 500)
      expect(cost).to be_within(0.0000001).of((0.0000025 * 1000) + (0.00001 * 500))
    end

    it "strips date suffix to match a versioned name" do
      cost = service.cost_usd(model: "claude-haiku-4-5-20251001", input_tokens: 100, output_tokens: 50)
      expect(cost).to be_within(0.0000001).of((0.0000008 * 100) + (0.000004 * 50))
    end

    it "strips version numbers to match a base name" do
      # catalog has "claude-sonnet" but not "claude-sonnet-4-99"
      cost = service.cost_usd(model: "claude-sonnet-4-99", input_tokens: 1000, output_tokens: 200)
      expect(cost).to be_within(0.0000001).of((0.000003 * 1000) + (0.000015 * 200))
    end

    it "returns 0.0 for an unknown model" do
      cost = service.cost_usd(model: "unknown-model-xyz", input_tokens: 1000, output_tokens: 500)
      expect(cost).to eq(0.0)
    end

    it "returns 0.0 when token counts are zero" do
      cost = service.cost_usd(model: "gpt-4o", input_tokens: 0, output_tokens: 0)
      expect(cost).to eq(0.0)
    end
  end

  describe "caching" do
    before do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    end

    it "fetches remote only once across multiple calls" do
      service.cost_usd(model: "gpt-4o", input_tokens: 100, output_tokens: 50)
      service.cost_usd(model: "gpt-4o", input_tokens: 200, output_tokens: 100)
      expect(service).to have_received(:fetch_remote).once
    end

    it "falls back to stale cache when remote fetch fails" do
      Rails.cache.write(ModelPricingService::STALE_CACHE_KEY, catalog)
      allow(service).to receive(:fetch_remote).and_return(nil)

      cost = service.cost_usd(model: "gpt-4o", input_tokens: 1000, output_tokens: 500)
      expect(cost).to be > 0.0
    end

    it "returns 0.0 when remote fails and no stale cache exists" do
      allow(service).to receive(:fetch_remote).and_return(nil)

      cost = service.cost_usd(model: "gpt-4o", input_tokens: 1000, output_tokens: 500)
      expect(cost).to eq(0.0)
    end
  end

  describe ".cost_usd (class method)" do
    it "delegates to an instance" do
      allow_any_instance_of(described_class).to receive(:fetch_remote).and_return(catalog)
      cost = described_class.cost_usd(model: "gpt-4o", input_tokens: 1000, output_tokens: 500)
      expect(cost).to be > 0.0
    end
  end

  describe "#rates_for" do
    it "returns per-million input and output rates for a known model" do
      rates = service.rates_for("gpt-4o")
      expect(rates[:input_per_million]).to  eq((0.0000025 * 1_000_000).round(4))
      expect(rates[:output_per_million]).to eq((0.00001   * 1_000_000).round(4))
    end

    it "returns nil for an unknown model" do
      expect(service.rates_for("unknown-model-xyz")).to be_nil
    end

    it "strips version suffix to find rates" do
      rates = service.rates_for("claude-sonnet-4-99")
      expect(rates).not_to be_nil
      expect(rates[:input_per_million]).to eq((0.000003 * 1_000_000).round(4))
    end
  end
end
