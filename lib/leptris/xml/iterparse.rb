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
# v2 (libleptris 1.9.4, #586): an explicit yield mode —
# :top_level (v1: the root's completed children) or
# :full_document (every element in document-order completion —
# post-order, child before parent, subtree attached) — plus
# namespace resolution on the last yielded element and an error
# channel for truncated input:
#
#     it = Leptris::XML::Iterparse.parse(xml, mode: :full_document)
#     it.run do |el|
#       it.namespace_uri("p")   # in scope on el, the last yielded
#     end
#     it.free
#
#     Leptris::XML::Iterparse.parse(xml) { |el| ... }.error
#     # => nil, or the parse failure (readable after the run: the
#     #    block form frees the iterator on return, snapshotting it)
#
# The yielded elements have no parent Document; #document returns
# nil and they must not outlive the iteration.
class Leptris::XML::Iterparse
  MODES = {
    top_level: Leptris::XML::FFI::ITERPARSE_TOP_LEVEL,
    full_document: Leptris::XML::FFI::ITERPARSE_FULL_DOCUMENT,
  }.freeze

  # NOTE: an IO argument is read fully into memory before the C
  # iterator starts — the bounded-memory path is parse_file (C-side
  # file streaming). The C API takes one (xml, len) buffer.
  def self.parse(xml_or_io, mode: :top_level, &block)
    xml = xml_or_io.respond_to?(:read) ? xml_or_io.read : xml_or_io.to_s
    iterator = new(Leptris::XML::FFI.leptris_iterparse_new_ex(
      xml, xml.bytesize, mode_code(mode)))
    return iterator unless block
    begin
      iterator.run(&block)
    ensure
      iterator.free
    end
    iterator
  end

  def self.parse_file(path, mode: :top_level, &block)
    iterator = new(Leptris::XML::FFI.leptris_iterparse_new_file_ex(
      path, mode_code(mode)))
    return iterator unless block
    begin
      iterator.run(&block)
    ensure
      iterator.free
    end
    iterator
  end

  def self.mode_code(mode)
    MODES.fetch(mode) do
      raise ArgumentError,
        "mode must be :top_level or :full_document, got #{mode.inspect}"
    end
  end
  private_class_method :mode_code

  def initialize(handle)
    raise Leptris::XML::ParseError, "leptris_iterparse_new failed" if handle.null?
    @handle = handle
  end

  # Yields completed elements until the document is exhausted or the
  # parse fails (see #error). Does not free the iterator — the block
  # form of .parse/.parse_file does, or call #free explicitly.
  def run
    return enum_for(:run) unless block_given?
    while @handle
      ptr = Leptris::XML::FFI.leptris_iterparse_next(@handle)
      break if ptr.null?
      # document: nil — the subtree belongs to the iterator's pool,
      # not a long-lived Document, so wrapper caching is skipped and
      # #document is nil on the yielded elements.
      yield Leptris::XML::Node.wrap(ptr, nil)
    end
    self
  end

  # The URI bound to +prefix+ ("" for the default namespace) in the
  # last yielded element's in-scope namespace snapshot, or nil when
  # unbound (v2, #586). Valid only while the iterator is live —
  # call it inside the #run block; nil after #free.
  def namespace_uri(prefix)
    return nil if @handle.nil?
    Leptris::XML::FFI.leptris_iterparse_ns_uri(@handle, prefix.to_s)
  end

  # Number of namespace bindings in the last yielded element's
  # scope. Valid only while the iterator is live; 0 after #free.
  def namespace_count
    return 0 if @handle.nil?
    Leptris::XML::FFI.leptris_iterparse_ns_count(@handle)
  end

  # The parse error for malformed/truncated input, or nil when the
  # document is well-formed and exhausted. Yielded elements stop at
  # the failure point; #free snapshots the message so this stays
  # readable after the block form of .parse returns.
  def error
    @handle ? live_error : @last_error
  end

  # Releases the C iterator. Safe to call twice.
  def free
    return if @handle.nil?
    @last_error = live_error
    Leptris::XML::FFI.leptris_iterparse_free(@handle)
    @handle = nil
  end

  private

  def live_error
    msg = Leptris::XML::FFI.leptris_iterparse_error(@handle)
    msg.nil? || msg.empty? ? nil : msg
  end
end
