# frozen_string_literal: true

require "leptris"
# Explicit: some contexts resolve a root without the facade
# autoloads registered; the require is idempotent.
require "leptris/html"

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
