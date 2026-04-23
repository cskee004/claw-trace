require "set"

# Compares two traces by computing stat deltas and span-name set membership.
# No span matching algorithm — spans are matched by name only.
class TraceComparator
  Result = Struct.new(:stats, :names_a, :names_b, keyword_init: true)

  def self.call(trace_a, trace_b)
    spans_a = trace_a.spans.to_a
    spans_b = trace_b.spans.to_a

    stats = {
      input_tokens_a:  spans_a.sum { |s| s.span_input_tokens.to_i },
      input_tokens_b:  spans_b.sum { |s| s.span_input_tokens.to_i },
      output_tokens_a: spans_a.sum { |s| s.span_output_tokens.to_i },
      output_tokens_b: spans_b.sum { |s| s.span_output_tokens.to_i },
      cost_usd_a:      spans_a.sum { |s| s.span_cost_usd.to_f }.round(6),
      cost_usd_b:      spans_b.sum { |s| s.span_cost_usd.to_f }.round(6),
      duration_ms_a:   TraceDurationCalculator.call(trace_a),
      duration_ms_b:   TraceDurationCalculator.call(trace_b),
      error_count_a:   spans_a.count { |s| s.span_outcome == "error" },
      error_count_b:   spans_b.count { |s| s.span_outcome == "error" },
      span_counts_a:   spans_a.group_by(&:span_type).transform_values(&:size),
      span_counts_b:   spans_b.group_by(&:span_type).transform_values(&:size),
    }

    names_a = Set.new(spans_a.filter_map(&:span_name))
    names_b = Set.new(spans_b.filter_map(&:span_name))

    Result.new(stats: stats, names_a: names_a, names_b: names_b)
  end
end
