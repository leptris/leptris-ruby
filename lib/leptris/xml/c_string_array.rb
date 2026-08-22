# frozen_string_literal: true

# Adapter for libleptris's NULL-terminated char** wire format. Both
# directions of the conversion live here so the pointer arithmetic has
# one home (previously c14n built the array by hand and SAX walked it
# by hand).
module Leptris::XML::CStringArray
  # Ruby strings -> NULL-terminated char**. Returns [buffer, anchors];
  # the caller must keep both referenced for the duration of the FFI
  # call (e.g. via local variables).
  def self.to_c(strings)
    strs = Array(strings).map(&:to_s)
    return [nil, nil] if strs.empty?

    ptr_size = ::FFI::type_size(:pointer)
    buffer = ::FFI::MemoryPointer.new(:pointer, strs.size + 1)
    anchors = strs.map { |s| ::FFI::MemoryPointer.from_string(s) }
    anchors.each_with_index { |p, i| buffer.put_pointer(i * ptr_size, p) }
    buffer.put_pointer(strs.size * ptr_size, nil)
    [buffer, anchors]
  end

  # NULL-terminated char** -> Ruby strings. Stops at the first NULL
  # entry. Returns [] for a NULL pointer.
  def self.to_ruby(ptr)
    return [] if ptr.nil? || ptr.null?

    ptr_size = ::FFI::type_size(:pointer)
    result = []
    offset = 0
    while (entry = ptr.get_pointer(offset)) && !entry.null?
      result << entry.read_string
      offset += ptr_size
    end
    result
  end
end
