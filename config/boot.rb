ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.

# bootsnap is CRuby-oriented (native cache); skip quietly on JRuby.
begin
  require "bootsnap/setup"
rescue LoadError
  # optional
end
