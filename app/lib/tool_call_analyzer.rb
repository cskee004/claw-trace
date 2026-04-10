# Analyzes tool call frequency and success rates across a set of Span records.
# Only spans with span_type "tool_result" are considered — these carry both
# tool_name and success in their metadata hash.
class ToolCallAnalyzer
  # spans — Array or ActiveRecord::Relation of Span records
  # Returns { "tool_name" => { calls: Integer, successes: Integer, success_rate: Float } }
  # Only tool_result spans are considered — they carry both tool_name and success in metadata.
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
      .group_by { |s| s.metadata["tool_name"] }
      .transform_values { |group| stats_for(group) }
  end

  private

  def tool_results
    Array(@spans).select { |s| s.span_type == "tool_result" }
  end

  def stats_for(group)
    total     = group.size
    successes = group.count { |s| s.metadata["success"] == true }
    {
      calls:        total,
      successes:    successes,
      success_rate: successes.to_f / total
    }
  end
end
