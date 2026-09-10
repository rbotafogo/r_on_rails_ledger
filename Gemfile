source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3", ">= 8.1.3.1"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"

# SQLite: native C extension on CRuby / MRI; JDBC on JRuby.
# Rails 8.1 SQLite cast_type fix: jruby/activerecord-jdbc-adapter#1225 (fork until merged).
gem "sqlite3", ">= 2.1", platforms: :ruby
platform :jruby do
  gem "activerecord-jdbc-adapter", github: "k0kubun/activerecord-jdbc-adapter",
      ref: "422254ac421bc0be56edac527789aa9bde86d55e"
  gem "activerecord-jdbcsqlite3-adapter", github: "k0kubun/activerecord-jdbc-adapter",
      ref: "422254ac421bc0be56edac527789aa9bde86d55e"
end

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb (CRuby).
gem "bootsnap", require: false, platforms: :ruby

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false, platforms: :ruby

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2", platforms: :ruby

# R-on-Rails: GNU R bridge (CRuby or JRuby — same gem).
#
# Default: published gem from RubyGems.
# Optional local checkout: GALAAZ_GEM_PATH=/path/to/galaaz bundle install
# require: false — boot Rails without spawning GNU R (CI / importmap / empty tests).
# Risk engines still `require "galaaz"` when they run.
galaaz_path = ENV["GALAAZ_GEM_PATH"].to_s
if !galaaz_path.empty? && Dir.exist?(galaaz_path)
  gem "galaaz", path: galaaz_path, require: false
else
  gem "galaaz", require: false
end
gem "msgpack" # NewBridge wire format (also a galaaz dependency)
gem "csv"     # seeds / GBM panel generation
# ActiveSupport::JSON.decode still calls JSON.parse(str, options) positionally;
# json 3.x requires **kwargs (breaks AR json columns on JRuby).
gem "json", "~> 2.15"
# Markdown for in-app docs: C extension on MRI; pure Ruby on JRuby.
gem "redcarpet", platforms: :ruby
gem "kramdown", platforms: :jruby
gem "kramdown-parser-gfm", platforms: :jruby
gem "benchmark" # seeds.rb timing; not a default gem on Ruby 3.4+/4.0

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
end
