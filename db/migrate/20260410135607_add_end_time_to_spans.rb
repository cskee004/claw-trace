class AddEndTimeToSpans < ActiveRecord::Migration[8.0]
  def change
    add_column :spans, :end_time, :datetime
  end
end
