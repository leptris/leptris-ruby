# frozen_string_literal: true

require "leptris/version"

module Leptris
  autoload :XML, "leptris/xml"
end

# Eager library resolution (issue leptris-ruby#49): resolve the
# native library at require time instead of lazily inside
# Document.parse, so a missing library fails immediately.
#
# The require MUST come after the autoload registration above.
# ffi.rb opens `module Leptris; module XML`, and when that runs
# before `autoload :XML` exists it creates the constant first — the
# later autoload registration is then shadowed, xml.rb never loads,
# and the entire API is unreachable (Leptris::XML.constants ==
# [:FFI]; issue leptris-ruby#53). Requiring from here after the
# registration makes ffi.rb's module opening trigger the autoload,
# landing FFI inside the real manifest module; a downstream
# `require "leptris/xml"` is then a no-op.
begin
  require "leptris/xml/ffi"
rescue LoadError => e
  raise LoadError, <<~MSG
    Leptris could not load the native libleptris library.
    The ruby-platform gem is a fallback variant and ships no
    binary; install the platform-specific variant for your system
    (e.g. `gem install leptris --platform=arm64-darwin`), or set
    LEPTRIS_LIB_PATH to a libleptris.{so,dylib,dll} file.
    (Underlying error: #{e.message})
  MSG
end

# TODO.perf/02: auto-enable the native acceleration layer when the
# compiled bundle is present (platform gems). Quietly falls back
# to pure FFI when absent (ruby-variant on TruffleRuby/JRuby,
# custom builds). LEPTRIS_NO_NATIVE=1 forces the FFI path (the
# suite uses it to exercise both surfaces). The explicit
# `require "leptris/xml/native_layer"` remains the parallel-API
# entry for NativeNode builders.
unless ENV["LEPTRIS_NO_NATIVE"] == "1"
  begin
    require "leptris/xml/native_layer"
  rescue LoadError => e
    # #207: a silent fallback hides a platform-gem packaging bug
    # behind a walk-speed regression. Say so, then continue on
    # the FFI surface (the explicit require still raises its full
    # error for callers that opt in).
    warn "leptris: native acceleration unavailable " \
         "(#{e.message.lines.first.strip}); using the FFI surface"
  end
end
