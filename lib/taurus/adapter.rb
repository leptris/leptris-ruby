# frozen_string_literal: true

# Load Moxml-compatible adapters if available
begin
  require "moxml"
  require_relative "adapter/taurus"
rescue LoadError
  # Moxml not available, skip Moxml adapters
end
