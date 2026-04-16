require "uri"

module TracesHelper
  # Returns a hash mapping each span_id to its nesting depth (0 = root).
  # Depth is computed by walking the parent_span_id chain until nil or a
  # parent not present in the given span set.
  #
  # Input:  array of objects responding to #span_id and #parent_span_id
  # Output: { span_id (String) => depth (Integer) }
  def span_depth_map(spans)
    id_to_parent = spans.each_with_object({}) { |s, h| h[s.span_id] = s.parent_span_id }

    spans.each_with_object({}) do |span, depths|
      depth = 0
      current = span.parent_span_id
      while current && id_to_parent.key?(current)
        depth += 1
        current = id_to_parent[current]
      end
      depths[span.span_id] = depth
    end
  end

  # Returns spans in DFS pre-order so each parent immediately precedes its
  # entire subtree in the list, regardless of timestamp ordering.
  # Within each parent, children are visited in ascending timestamp order.
  # Spans whose parent is absent from the set are treated as roots.
  #
  # Input:  array of objects responding to #span_id, #parent_span_id, #timestamp
  # Output: ordered array of the same objects
  def dfs_ordered_spans(spans)
    return [] if spans.empty?

    id_set = spans.each_with_object({}) { |s, h| h[s.span_id] = true }
    children = Hash.new { |h, k| h[k] = [] }

    spans.each do |span|
      parent = span.parent_span_id
      key = (parent && id_set.key?(parent)) ? parent : nil
      children[key] << span
    end

    result = []
    stack = children[nil].sort_by(&:timestamp).reverse

    until stack.empty?
      span = stack.pop
      result << span
      kids = children[span.span_id].sort_by(&:timestamp).reverse
      stack.push(*kids)
    end

    result
  end

  # Returns a short display string for a span based on its type and metadata.
  # Used to show contextual info (model name, HTTP method+host, tool name) next to each span.
  # Checks first-class columns before falling back to the metadata hash.
  # Returns nil when no relevant metadata is available.
  def span_accent(span)
    case span.span_type
    when "model_call"
      span.span_model.presence || span.metadata&.dig("openclaw.model")
    when "message_event"
      span.metadata&.dig("openclaw.channel")
    when "tool_call"
      span.metadata&.dig("openclaw.tool") ||
        span.metadata&.dig("tool.name")
    when "session_event"
      span.metadata&.dig("openclaw.channel")
    else
      nil
    end
  end

  # Exposed as module_function so TracesController can call TracesHelper.dfs_ordered_spans
  # directly without a view context. span_depth_map is view-only and does not need this.
  module_function :dfs_ordered_spans
end
