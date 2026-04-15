class DropApiKeys < ActiveRecord::Migration[8.0]
  def up
    drop_table :api_keys
  end

  def down
    create_table :api_keys do |t|
      t.string  :token,      null: false
      t.string  :agent_type
      t.boolean :active,     null: false, default: true
      t.timestamps
    end
    add_index :api_keys, :token, unique: true
  end
end
