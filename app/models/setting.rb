# Stores application configuration as key-value pairs.
# Keys are unique strings; values are always stored as text.
#
# Use Setting.get / Setting.set — never query the table directly.
class Setting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  def self.get(key, default: nil)
    find_by(key: key)&.value || default
  end

  def self.set(key, value)
    upsert({ key: key, value: value.to_s }, unique_by: :key)
  end
end
