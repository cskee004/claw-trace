class AddSpanCostUsdToSpans < ActiveRecord::Migration[8.0]
  def change
    add_column :spans, :span_cost_usd, :decimal, precision: 10, scale: 8
  end
end
