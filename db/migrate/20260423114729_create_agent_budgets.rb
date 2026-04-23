class CreateAgentBudgets < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_budgets do |t|
      t.string  :agent_id,        null: false
      t.decimal :daily_limit_usd, precision: 10, scale: 4, null: false
      t.timestamps
    end

    add_index :agent_budgets, :agent_id, unique: true
  end
end
