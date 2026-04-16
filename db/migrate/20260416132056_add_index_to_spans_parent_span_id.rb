class AddIndexToSpansParentSpanId < ActiveRecord::Migration[8.0]
  def change
    add_index :spans, :parent_span_id
  end
end
