source "https://rubygems.org"

# clawtrace.gemspec defines gem metadata and distribution dependencies.
# Not referenced here via `gemspec` to prevent Bundler from auto-requiring
# lib/clawtrace.rb (which loads the Rails::Engine and causes double route
# drawing in standalone app mode).

gem 'pg', group: :production, platforms: :ruby

gem "rails", "~> 8.0.2"
gem "propshaft"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "jbuilder"

gem "tzinfo-data", platforms: %i[windows jruby]

gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

gem "bootsnap", require: false
gem "kamal", require: false
gem "thruster", require: false

group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
  gem 'guard-livereload', require: false
  gem 'rspec-rails'
  gem "rails-controller-testing"
  gem "sqlite3", ">= 2.1"
end

group :development do
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end

gem "hotwire-livereload", "~> 2.0", group: :development
gem "tailwindcss-rails"
