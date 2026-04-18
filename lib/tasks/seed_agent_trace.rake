namespace :db do
  namespace :seed do
    desc "Seed the agent trace fixture for visual timeline testing"
    task trace: :environment do
      trace_id = "a9f3e12b4c5d6e7f"

      if Trace.exists?(trace_id: trace_id)
        puts "Agent trace fixture already present (#{trace_id}) — skipping."
        puts "View at: http://localhost:3000/traces/#{trace_id}"
        next
      end

      fixture_path = Rails.root.join(".claude/json-test-files/otlp-agent-trace-fixture.json")
      json = File.read(fixture_path)

      results = OtlpNormalizer.call(json)
      results.each { |r| TelemetryIngester.call(**r) }

      puts "Seeded agent trace: #{trace_id}"
      puts "View at: http://localhost:3000/traces/#{trace_id}"
    end
  end
end
