require "rails_helper"

RSpec.describe Log, type: :model do
  let(:trace) do
    Trace.create!(
      trace_id:   "a1b2c3d4e5f6a7b8",
      agent_id:   "support-agent",
      task_name:  "handle_ticket",
      start_time: Time.utc(2026, 4, 10, 12, 0, 0),
      status:     :in_progress
    )
  end

  def valid_attrs(overrides = {})
    {
      timestamp:      Time.utc(2026, 4, 10, 12, 0, 1),
      log_attributes: {}
    }.merge(overrides)
  end

  describe "validations" do
    it "is valid with only required attributes" do
      expect(Log.new(valid_attrs)).to be_valid
    end

    it "requires timestamp" do
      expect(Log.new(valid_attrs(timestamp: nil))).not_to be_valid
    end

    it "rejects nil log_attributes" do
      expect(Log.new(valid_attrs(log_attributes: nil))).not_to be_valid
    end

    it "accepts an empty log_attributes hash" do
      expect(Log.new(valid_attrs(log_attributes: {}))).to be_valid
    end

    it "allows trace_id to be nil" do
      expect(Log.new(valid_attrs(trace_id: nil))).to be_valid
    end

    it "allows span_id to be nil" do
      expect(Log.new(valid_attrs(span_id: nil))).to be_valid
    end

    it "allows severity_text to be nil" do
      expect(Log.new(valid_attrs(severity_text: nil))).to be_valid
    end

    it "allows severity_number to be nil" do
      expect(Log.new(valid_attrs(severity_number: nil))).to be_valid
    end

    it "allows body to be nil" do
      expect(Log.new(valid_attrs(body: nil))).to be_valid
    end
  end

  describe "associations" do
    it "belongs to a trace via trace_id when present" do
      log = Log.create!(valid_attrs(trace_id: trace.trace_id))
      expect(log.trace).to eq(trace)
    end

    it "is valid without a matching trace" do
      log = Log.new(valid_attrs(trace_id: "0000000000000000"))
      expect(log).to be_valid
    end

    it "is valid with no trace_id at all" do
      log = Log.new(valid_attrs(trace_id: nil))
      expect(log).to be_valid
    end
  end

  describe "JSON column" do
    it "persists and retrieves log_attributes" do
      attrs = { "service.name" => "clawtrace", "gen_ai.system" => "anthropic" }
      log = Log.create!(valid_attrs(log_attributes: attrs))
      expect(log.reload.log_attributes).to eq(attrs)
    end
  end

  describe "nullable text fields" do
    it "persists severity_text" do
      log = Log.create!(valid_attrs(severity_text: "WARN"))
      expect(log.reload.severity_text).to eq("WARN")
    end

    it "persists severity_number" do
      log = Log.create!(valid_attrs(severity_number: 13))
      expect(log.reload.severity_number).to eq(13)
    end

    it "persists body" do
      log = Log.create!(valid_attrs(body: "token limit reached"))
      expect(log.reload.body).to eq("token limit reached")
    end

    it "persists span_id" do
      log = Log.create!(valid_attrs(span_id: "ab12cd34ef56a1b2"))
      expect(log.reload.span_id).to eq("ab12cd34ef56a1b2")
    end
  end
end
