# frozen_string_literal: true

# Parser flags, mirroring LeptrisParseFlags in libleptris's public
# headers. Pass an instance as `Leptris::XML.parse(xml, options:)`.
class Leptris::XML::ParseOptions
  # Discard whitespace-only text nodes (runs between tags that contain
  # nothing but spaces/tabs/newlines). Matches libxml2's
  # XML_PARSE_NOBLANKS and Nokogiri's noblanks. Documents parsed this
  # way do not round-trip pretty-printed formatting byte-for-byte.
  NOBLANKS = Leptris::XML::FFI::LEPTRIS_PARSE_DROP_WS_TEXT

  attr_reader :flags

  def initialize(flags = Leptris::XML::FFI::LEPTRIS_PARSE_DEFAULT)
    @flags = flags.to_i
  end

  def self.noblanks
    new(NOBLANKS)
  end

  def noblanks?
    @flags & NOBLANKS != 0
  end

  def |(other)
    self.class.new(@flags | other.flags)
  end
end
