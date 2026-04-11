class AddNameToSpans < ActiveRecord::Migration[8.0]
  def change
    add_column :spans, :name, :string
  end
end
