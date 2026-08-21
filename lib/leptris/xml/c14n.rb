# frozen_string_literal: true

module Leptris
  module XML
    # @api private
    #
    # Builds a NULL-terminated `const char**` from a Ruby array of strings,
    # suitable for passing to leptris_c14n_canonicalize_ex's
    # `inclusive_ns_prefixes` argument. Returns [pointer, anchor] where
    # anchor is the underlying MemoryPointer that the caller must keep
    # alive (e.g. via local variable) for the duration of the FFI call.
    def self.c14n_build_ns_pointer(inclusive_namespaces)
      return [nil, nil] if inclusive_namespaces.nil? || inclusive_namespaces.empty?
      strs = Array(inclusive_namespaces).map(&:to_s)
      ptr_size = ::FFI.type_size(:pointer)
      buffer = ::FFI::MemoryPointer.new(:pointer, strs.size + 1)
      anchors = strs.map { |s| ::FFI::MemoryPointer.from_string(s) }
      anchors.each_with_index { |p, i| buffer.put_pointer(i * ptr_size, p) }
      buffer.put_pointer(strs.size * ptr_size, nil)
      [buffer, anchors]
    end
  end
end
