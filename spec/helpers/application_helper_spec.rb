require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  include ApplicationHelper

  describe "#format_time_absolute" do
    it "returns HH:MM:SS in UTC" do
      time = Time.utc(2026, 4, 14, 15, 23, 45)
      expect(format_time_absolute(time)).to eq("15:23:45")
    end

    it "converts non-UTC time to UTC before formatting" do
      time = ActiveSupport::TimeZone["Eastern Time (US & Canada)"].local(2026, 4, 14, 11, 0, 0)
      expect(format_time_absolute(time)).to eq("15:00:00")
    end
  end

  describe "#format_time_relative" do
    let(:now) { Time.utc(2026, 4, 14, 15, 0, 0) }

    it "returns 'just now' for times less than 60 seconds ago" do
      expect(format_time_relative(now - 30, now: now)).to eq("just now")
    end

    it "returns 'just now' for times exactly 0 seconds ago" do
      expect(format_time_relative(now, now: now)).to eq("just now")
    end

    it "returns '1 min ago' for 60 seconds ago" do
      expect(format_time_relative(now - 60, now: now)).to eq("1 min ago")
    end

    it "returns 'N min ago' for times between 1 and 59 minutes ago" do
      expect(format_time_relative(now - 45 * 60, now: now)).to eq("45 min ago")
    end

    it "returns '1 hr ago' for exactly 3600 seconds ago" do
      expect(format_time_relative(now - 3600, now: now)).to eq("1 hr ago")
    end

    it "returns 'N hr ago' for times between 1 and 23 hours ago" do
      expect(format_time_relative(now - 5 * 3600, now: now)).to eq("5 hr ago")
    end

    it "returns 'Yesterday' for a time on the previous calendar day" do
      yesterday = Time.utc(2026, 4, 13, 10, 0, 0)
      expect(format_time_relative(yesterday, now: now)).to eq("Yesterday")
    end

    it "returns 'Yesterday' even when the gap is more than 24 hours (midnight boundary)" do
      now_midnight = Time.utc(2026, 4, 14, 0, 5, 0)
      event        = Time.utc(2026, 4, 13, 23, 50, 0)
      expect(format_time_relative(event, now: now_midnight)).to eq("Yesterday")
    end

    it "returns 'Sat 11' format for times 2-6 days ago" do
      sat = Time.utc(2026, 4, 11, 10, 0, 0)
      expect(format_time_relative(sat, now: now)).to eq("Sat 11")
    end

    it "returns 'Apr 4' format for times in the same year but beyond 7 days" do
      apr4 = Time.utc(2026, 4, 4, 10, 0, 0)
      expect(format_time_relative(apr4, now: now)).to eq("Apr 4")
    end

    it "returns 'Nov 3, 2024' for times in a prior year" do
      old = Time.utc(2024, 11, 3, 10, 0, 0)
      expect(format_time_relative(old, now: now)).to eq("Nov 3, 2024")
    end
  end
end
