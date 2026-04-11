class RenameNameToSpanNameOnSpans < ActiveRecord::Migration[8.0]
  def change
    rename_column :spans, :name, :span_name
  end
end
