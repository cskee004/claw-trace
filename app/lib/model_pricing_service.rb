class ModelPricingService
  CACHE_KEY       = "model_pricing_service/prices"
  STALE_CACHE_KEY = "model_pricing_service/prices_stale"
  CACHE_TTL       = 24.hours
  PRICING_URL     = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"

  def self.cost_usd(model:, input_tokens:, output_tokens:)
    new.cost_usd(model: model, input_tokens: input_tokens, output_tokens: output_tokens)
  end

  def cost_usd(model:, input_tokens:, output_tokens:)
    prices = find_prices(model)
    return 0.0 unless prices

    (prices[:input] * input_tokens.to_i) + (prices[:output] * output_tokens.to_i)
  end

  private

  def find_prices(model)
    catalog = fetch_catalog

    candidate_names(model).each do |name|
      prices = extract_prices(catalog[name])
      return prices if prices
    end

    nil
  end

  # Produces lookup candidates from most-specific to least-specific.
  # "claude-haiku-4-5-20251001" => ["claude-haiku-4-5-20251001", "claude-haiku-4-5", "claude-haiku"]
  # "claude-sonnet-4-6"         => ["claude-sonnet-4-6", "claude-sonnet"]
  # "gpt-4o"                    => ["gpt-4o"]
  def candidate_names(model)
    names = [model]
    no_date = model.sub(/-\d{8}$/, "")
    names << no_date if no_date != model
    base = no_date.sub(/(-\d[\d.]*)+$/, "")
    names << base if base != no_date
    names
  end

  def fetch_catalog
    cached = Rails.cache.read(CACHE_KEY)
    return cached if cached

    remote = fetch_remote
    if remote
      Rails.cache.write(CACHE_KEY, remote, expires_in: CACHE_TTL)
      Rails.cache.write(STALE_CACHE_KEY, remote)
      remote
    else
      Rails.cache.read(STALE_CACHE_KEY) || {}
    end
  rescue StandardError
    Rails.cache.read(STALE_CACHE_KEY) || {}
  end

  def fetch_remote
    require "net/http"
    uri = URI(PRICING_URL)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 10) do |http|
      http.get(uri.path)
    end
    JSON.parse(response.body)
  rescue StandardError => e
    Rails.logger.warn("ModelPricingService: remote fetch failed — #{e.message}")
    nil
  end

  def extract_prices(entry)
    return nil unless entry.is_a?(Hash)
    input  = entry["input_cost_per_token"]
    output = entry["output_cost_per_token"]
    return nil unless input && output
    { input: input.to_f, output: output.to_f }
  end
end
