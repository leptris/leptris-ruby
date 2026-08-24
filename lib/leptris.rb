# frozen_string_literal: true

require "leptris/version"

module Leptris
  # Eager library resolution (issue leptris-ruby#49): autoload made
  # ffi_lib lazy, so a ruby-platform gem (no vendored libleptris)
  # failed deep inside Document.parse instead of at require time.
  # Loading the FFI module NOW turns that into an immediate,
  # actionable LoadError.
  require "leptris/xml/ffi"

  autoload :XML, "leptris/xml"
end
