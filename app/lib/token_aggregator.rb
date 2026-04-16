class TokenAggregator
  def self.call(spans)
    rows = spans.where(span_type: "model_call")
                .pick(
                  Arel.sql("COALESCE(SUM(span_input_tokens), 0)"),
                  Arel.sql("COALESCE(SUM(span_output_tokens), 0)"),
                  Arel.sql("COALESCE(SUM(span_cache_read_tokens), 0)"),
                  Arel.sql("COALESCE(SUM(span_cache_write_tokens), 0)"),
                  Arel.sql("COALESCE(SUM(span_total_tokens), 0)")
                )

    input, output, cache_read, cache_write, total = rows.map(&:to_i)

    denominator = input + cache_read
    ratio = denominator > 0 ? (cache_read.to_f / denominator * 100).round(1) : nil

    {
      input_tokens:     input,
      output_tokens:    output,
      cache_read_tokens:  cache_read,
      cache_write_tokens: cache_write,
      total_tokens:     total,
      cache_hit_ratio:  ratio
    }
  end
end
