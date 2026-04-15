require "rails_helper"

RSpec.describe Setting, type: :model do
  describe "validations" do
    it "requires key" do
      expect(Setting.new(value: "30")).not_to be_valid
    end

    it "requires key to be unique" do
      Setting.create!(key: "log_retention_days", value: "30")
      expect(Setting.new(key: "log_retention_days", value: "60")).not_to be_valid
    end
  end

  describe ".get" do
    it "returns nil when key does not exist and no default given" do
      expect(Setting.get("nonexistent")).to be_nil
    end

    it "returns the default when key does not exist" do
      expect(Setting.get("nonexistent", default: "42")).to eq("42")
    end

    it "returns the stored value when key exists" do
      Setting.create!(key: "log_retention_days", value: "90")
      expect(Setting.get("log_retention_days")).to eq("90")
    end

    it "returns the stored value over the default when key exists" do
      Setting.create!(key: "log_retention_days", value: "90")
      expect(Setting.get("log_retention_days", default: "30")).to eq("90")
    end
  end

  describe ".set" do
    it "creates a new row when key does not exist" do
      Setting.set("log_retention_days", "30")
      expect(Setting.find_by(key: "log_retention_days").value).to eq("30")
    end

    it "updates an existing row (upsert behaviour)" do
      Setting.create!(key: "log_retention_days", value: "30")
      Setting.set("log_retention_days", "90")
      expect(Setting.find_by(key: "log_retention_days").value).to eq("90")
      expect(Setting.where(key: "log_retention_days").count).to eq(1)
    end

    it "coerces the value to a string" do
      Setting.set("log_retention_days", 30)
      expect(Setting.find_by(key: "log_retention_days").value).to eq("30")
    end
  end
end
