namespace :spans do
  desc "Backfill span_cost_usd for model_call spans that have not been costed yet"
  task backfill_cost: :environment do
    scope   = Span.where.not(span_model: nil).where(span_cost_usd: nil)
    total   = scope.count
    updated = 0

    puts "Found #{total} model_call spans without span_cost_usd."

    scope.in_batches(of: 500) do |batch|
      batch.each do |span|
        cost = ModelPricingService.cost_usd(
          model:         span.span_model.to_s,
          input_tokens:  span.span_input_tokens.to_i,
          output_tokens: span.span_output_tokens.to_i
        )
        span.update_columns(span_cost_usd: cost) if cost > 0
        updated += 1
      end
    end

    puts "Backfilled #{updated} spans."
  end
end
