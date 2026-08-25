# frozen_string_literal: true

require "ffi"

# Incremental tree iteration (libleptris v1.6.0): yields each
# completed TOP-LEVEL child element of the document root as it
# parses. The previous element's whole subtree is released when the
# next is produced — memory stays bounded by the largest subtree,
# not the document.
#
#     Leptris::XML::Iterparse.parse(huge_xml) do |element|
#       process(element)   # subtree valid until the next iteration
#     end
#
# v1 limitation (upstream): element names are the QName as written;
# namespace prefixes are not re-resolved — use the DOM path when
# namespace URIs matter. The yielded elements have no parent
# Document; #document returns nil and they must not outlive the
# iteration.
class Leptris::XML::Iterparse
  # NOTE: an IO argument is read fully into memory before the C
  # iterator starts — the bounded-memory path is parse_file (C-side
  # file streaming). The C API takes one (xml, len) buffer.
  def self.parse(xml_or_io, &block)
    xml = xml_or_io.respond_to?(:read) ? xml_or_io.read : xml_or_io.to_s
    iterator = new(Leptris::XML::FFI.leptris_iterparse_new(xml, xml.bytesize))
    iterator.run(&block)
  end

  def self.parse_file(path, &block)
    iterator = new(Leptris::XML::FFI.leptris_iterparse_new_file(path))
    iterator.run(&block)
  end

  def initialize(handle)
    raise Leptris::XML::ParseError, "leptris_iterparse_new failed" if handle.null?
    @handle = handle
  end

  def run
    return enum_for(:run) unless block_given?
    loop do
      ptr = Leptris::XML::FFI.leptris_iterparse_next(@handle)
      break if ptr.null?
      # document: nil — the subtree belongs to the iterator's pool,
      # not a long-lived Document, so wrapper caching is skipped and
      # #document is nil on the yielded elements.
      yield Leptris::XML::Node.wrap(ptr, nil)
    end
    self
  ensure
    free
  end

  def free
    return if @handle.nil?
    Leptris::XML::FFI.leptris_iterparse_free(@handle)
    @handle = nil
  end
end
