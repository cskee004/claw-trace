# ModelPricingService

`app/lib/model_pricing_service.rb`

Fetches LLM token pricing from the LiteLLM pricing catalog and computes per-span cost estimates in USD.

---

## Interface

```ruby
# Compute cost for a single span
cost = ModelPricingService.cost_usd(
  model:         "claude-sonnet-4-6",
  input_tokens:  1200,
  output_tokens: 340
)
# => 0.00423   (Float, USD) or nil if model unknown

# Get per-million-token rates for display
rates = ModelPricingService.rates_for("claude-sonnet-4-6")
# => { input_per_million: 3.0, output_per_million: 15.0 } or nil
```

---

## Pricing Catalog

Prices are fetched from the [LiteLLM pricing JSON](https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json) — the same source used by many LLM proxy projects.

### Caching

| Cache layer | Key | TTL |
|-------------|-----|-----|
| Live cache | `model_pricing_service/prices` | 24 hours |
| Stale fallback | `model_pricing_service/prices_stale` | Never expires |

On startup (cold cache): prices are fetched from the remote URL and stored in both keys. After 24 hours the live key expires; the next call triggers a fresh fetch. If the remote fetch fails, the stale fallback is returned instead, so cost estimates continue to work even when the pricing URL is unreachable.

---

## Model Name Resolution

Model names are resolved from most-specific to least-specific:

| Input | Candidates tried |
|-------|-----------------|
| `"claude-haiku-4-5-20251001"` | `"claude-haiku-4-5-20251001"` → `"claude-haiku-4-5"` → `"claude-haiku"` |
| `"claude-sonnet-4-6"` | `"claude-sonnet-4-6"` → `"claude-sonnet"` |
| `"gpt-4o"` | `"gpt-4o"` |

The first candidate found in the pricing catalog is used. This handles date-versioned model strings (e.g. those with `-YYYYMMDD` suffixes) gracefully.

---

## Return Values

- `cost_usd` returns a `Float` (USD) when both input and output pricing are available, or `nil` if the model is not found in the catalog.
- `rates_for` returns `{ input_per_million: Float, output_per_million: Float }` or `nil`.

---

## Usage in Ingestion

`OtlpNormalizer` calls `ModelPricingService.cost_usd` for each span that carries a `span_model` value, storing the result in `span_cost_usd`. Spans without a model (e.g. `tool_call`, `agent_run_started`) receive `nil`.

```ruby
# Inside OtlpNormalizer
if model.present? && input_tokens && output_tokens
  span_hash["span_cost_usd"] = ModelPricingService.cost_usd(
    model: model, input_tokens: input_tokens, output_tokens: output_tokens
  )
end
```

---

## Backfilling Historical Spans

```bash
rails spans:backfill_cost
```

Iterates all `spans` where `span_model` is set but `span_cost_usd` is nil and updates them in batches of 500.
