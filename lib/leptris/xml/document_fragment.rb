# frozen_string_literal: true

require "ffi"

# Wraps the synthetic "#document-fragment" element returned by
# leptris_parse_fragment. Children of this fragment are the parsed nodes;
# the fragment itself isn't part of any document tree but borrows its
# document's lifetime.
class Leptris::XML::DocumentFragment
  attr_reader :document, :c_ptr

  def initialize(document, c_ptr)
    @document = document
    @c_ptr = c_ptr
  end

  def self.parse(xml, document)
    status_ptr = ::FFI::MemoryPointer.new(:int)
    raw = Leptris::XML::FFI.leptris_parse_fragment(
      xml.to_s, xml.to_s.bytesize, document.c_ptr, status_ptr)
    if raw.null?
      raise Leptris::XML::ParseError,
        "leptris_parse_fragment failed (status=#{status_ptr.read_int})"
    end
    new(document, raw)
  end

  def children
    Leptris::XML::Node.children_of(@c_ptr, @document)
  end

  def name
    "#document-fragment"
  end
end
