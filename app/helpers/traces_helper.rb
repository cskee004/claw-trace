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
end
