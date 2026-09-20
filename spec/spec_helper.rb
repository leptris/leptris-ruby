# frozen_string_literal: true

require "leptris"
# Explicit: some contexts resolve a root without the facade
# autoloads registered; the require is idempotent.
require "leptris/html"

# The build matrix's env expressions leave set-but-empty vars; the
# engine's getenv gate treats any non-null value as ENABLED, so
# LEPTRIS_DEBUG_ATTR_MISS="" turned attr-miss dumps on for every
# Ruby 3.4 leg (observed on ubuntu-24.04-arm). Empty means unset.
ENV.delete("LEPTRIS_DEBUG_ATTR_MISS") if ENV["LEPTRIS_DEBUG_ATTR_MISS"] == ""

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
