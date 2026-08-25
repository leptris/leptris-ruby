# frozen_string_literal: true

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
    raw, status = Leptris::XML::FFI.parse_fragment_with_status(
      xml.to_s, document.c_ptr)
    if raw.null?
      raise Leptris::XML::ParseError,
        "leptris_parse_fragment failed (status=#{status})"
    end
    new(document, raw)
  end

  def children
    nodes = Leptris::XML::FFI.fetch_children(@c_ptr).map do |ptr|
      Leptris::XML::Node.wrap(ptr, @document)
    end
    Leptris::XML::NodeSet.new(@document, nodes)
  end

  def name
    "#document-fragment"
  end
end
