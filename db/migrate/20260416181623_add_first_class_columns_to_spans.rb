class AddFirstClassColumnsToSpans < ActiveRecord::Migration[8.0]
  def change
    add_column :spans, :span_model, :string
    add_column :spans, :span_provider, :string
    add_column :spans, :span_input_tokens, :integer
    add_column :spans, :span_output_tokens, :integer
    add_column :spans, :span_cache_read_tokens, :integer
    add_column :spans, :span_cache_write_tokens, :integer
    add_column :spans, :span_total_tokens, :integer
    add_column :spans, :span_outcome, :string
  end
end
