# frozen_string_literal: true

require "ffi"

# External-DTD validation (libleptris >= 1.9.200, #1183): parse a
# DTD once, validate any number of documents against it — the engine
# counterpart of `leptris validate --dtd`.
#
#     dtd = Leptris::XML::DTD.parse(<<~DTD)
#       <!ELEMENT r (item+)>
#       <!ELEMENT item EMPTY>
#       <!ATTLIST item n CDATA #REQUIRED>
#     DTD
#     dtd.valid?(doc)     # => true/false
#     dtd.validate(doc)   # => nil when valid, else
#                         #    {message:, element_name:, line:, column:}
#
module Leptris::XML::DTD
  module_function

  # Parse a DTD (the external-subset grammar: ELEMENT/ATTLIST/
  # ENTITY/NOTATION declarations). Raises Leptris::XML::Error on
  # malformed input.
  def parse(dtd_text)
    raw = Leptris::XML::FFI.leptris_dtd_parse(dtd_text, dtd_text.bytesize)
    if raw.null?
      raise Leptris::XML::Error,
        "DTD parse failed: #{Leptris::XML::FFI.leptris_last_error}"
    end
    Handle.new(raw)
  end

  def parse_file(path)
    parse(File.read(path))
  end

  # A parsed, reusable DTD. Freed with the handle (AutoPointer).
  class Handle
    class Ref < ::FFI::AutoPointer
      def self.release(ptr)
        Leptris::XML::FFI.leptris_dtd_free(ptr)
      end
    end

    def initialize(ptr)
      @handle = Ref.new(ptr)
    end

    def valid?(document)
      Leptris::XML::FFI.leptris_dtd_validate(
        document.c_ptr, @handle, nil) == 1
    end

    # nil when the document conforms; otherwise the first violation
    # as {message:, element_name:, line:, column:}. The strings are
    # library-allocated copies valid until the next validate call.
    def validate(document)
      error = Leptris::XML::FFI::DTDError.new
      ok = Leptris::XML::FFI.leptris_dtd_validate(
        document.c_ptr, @handle, error)
      return nil if ok == 1

      msg = error[:message]
      name = error[:element_name]
      {
        message: msg.null? ? nil : msg.read_string,
        element_name: name.null? ? nil : name.read_string,
        line: error[:line],
        column: error[:column],
      }
    end
  end
end
