# frozen_string_literal: true

# Wraps the synthetic "#document-fragment" element returned by
# leptris_parse_fragment. Children of this fragment are the parsed nodes;
# the fragment itself isn't part of any document tree but borrows its
# document's lifetime.
class Leptris::XML::DocumentFragment
  include Leptris::XML::Searchable

  attr_reader :document, :c_ptr

  def initialize(document, c_ptr, c_address: nil)
    @document = document
    @c_ptr = c_ptr
    # TODO.perf/34: the address may arrive before any Pointer
    # exists (the C parse face returns an Integer).
    @c_address = c_address || c_ptr&.address
  end

  # Integer twin — reading it never materializes a Pointer.
  def c_address
    @c_address
  end

  def c_ptr
    @c_ptr ||= ::FFI::Pointer.new(@c_address)
  end

  def self.parse(xml, document)
    # TODO.perf/34: the C face answers the fragment address with
    # no status MemoryPointer and no Pointer mint; failures fall
    # back to the FFI pair for the exact error.
    if defined?(Leptris::XML::NATIVE_FAST)
      addr = Leptris::XML::Native.parse_fragment_addr(
        document, xml.to_s)
      return new(document, nil, c_address: addr) if addr != false
    end
    raw, status = Leptris::XML::FFI.parse_fragment_with_status(
      xml.to_s, document.c_ptr)
    if raw.null?
      raise Leptris::XML::ParseError,
        "leptris_parse_fragment failed (status=#{status})"
    end
    new(document, raw)
  end

  def children
    # TODO.perf/34: one C pass (fragment nodes live in the
    # document pool — the document's cache and version apply).
    if defined?(Leptris::XML::NATIVE_FAST)
      return Leptris::XML::Native.bulk_children(@document, @c_address)
    end
    pointers, kinds = Leptris::XML::FFI.fetch_children(c_ptr)
    nodes = Array.new(pointers.size) do |i|
      Leptris::XML::Node.wrap(pointers[i], @document, node_type: kinds[i])
    end
    Leptris::XML::NodeSet.new(@document, nodes)
  end

  def name
    "#document-fragment"
  end
end
