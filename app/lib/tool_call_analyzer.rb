# Analyzes tool call frequency and success rates across a set of Span records.
# Only spans with span_type "tool_call" are considered.
# Tool name comes from metadata["tool.name"]; success is span_outcome != "error".
class ToolCallAnalyzer
  # spans — Array or ActiveRecord::Relation of Span records
  # Returns { "tool.name value" => { calls: Integer, successes: Integer, success_rate: Float } }
  def self.call(spans)
    new(spans).call
  end

  def initialize(spans)
    @spans = spans
  end

  def call
    results = tool_results
    return {} if results.empty?

    results
      .group_by { |s| s.metadata["tool.name"] }
      .transform_values { |group| stats_for(group) }
  end

  private

  def tool_results
    Array(@spans).select { |s| s.span_type == "tool_call" }
  end

  def stats_for(group)
    total     = group.size
    successes = group.count { |s| s.span_outcome != "error" }
    {
      calls:        total,
      successes:    successes,
      success_rate: successes.to_f / total
    }
  end
end
