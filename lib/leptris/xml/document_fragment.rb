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
    count = Leptris::XML::FFI.leptris_element_child_count(@c_ptr)
    nodes = []
    ptr = Leptris::XML::FFI.leptris_node_first_child(@c_ptr)
    until ptr.nil? || ptr.null?
      nodes << Leptris::XML::Node.wrap(ptr, @document)
      ptr = Leptris::XML::FFI.leptris_node_next_sibling(ptr)
    end
    Leptris::XML::NodeSet.new(@document, nodes)
  end

  def name
    "#document-fragment"
  end
end
