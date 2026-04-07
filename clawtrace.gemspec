require_relative "lib/clawtrace/version"

Gem::Specification.new do |spec|
  spec.name        = "clawtrace"
  spec.version     = Clawtrace::VERSION
  spec.authors     = ["Chris Skeens"]
  spec.email       = ["cskee004@odu.edu"]
  spec.homepage    = "https://github.com/cskee004/clawtrace"
  spec.summary     = "Agent observability platform for OpenClaw"
  spec.description = "ClawTrace gives developers full visibility into how their " \
                     "OpenClaw agents think, act, and fail — with OTLP ingestion, " \
                     "trace/span storage, timeline views, and analysis engines for " \
                     "duration, tool usage, and error rates."
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 3.0"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "Rakefile", "README.md"]
      .reject { |f| File.directory?(f) }
  end

  spec.add_dependency "rails", ">= 8.0"
end
