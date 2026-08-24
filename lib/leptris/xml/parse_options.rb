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

  # Recover (libleptris 1.9.0, #547): a parse failure returns an
  # empty document with the failure recorded in Document#last_error
  # instead of raising — the libxml2 XML_PARSE_RECOVER semantics
  # adapters emulate. Struct-only (not a parse flag): carrying it
  # routes Document.parse through leptris_parse_string_ex.
  attr_reader :recover

  def initialize(flags = Leptris::XML::FFI::LEPTRIS_PARSE_DEFAULT,
                 recover: false)
    @flags = flags.to_i
    @recover = recover ? true : false
  end

  def self.noblanks
    new(NOBLANKS)
  end

  def self.recovering
    new(recover: true)
  end

  def noblanks?
    @flags & NOBLANKS != 0
  end

  def recover?
    @recover == true
  end

  def |(other)
    self.class.new(@flags | other.flags, recover: @recover || other.recover?)
  end

  # True when the options cannot ride the flags-only parse path and
  # need the full LeptrisParseOptions struct (leptris_parse_string_ex).
  def struct_required?
    recover?
  end

  # Builds the C LeptrisParseOptions struct mirroring this instance.
  def to_c_struct
    struct = Leptris::XML::FFI::ParseOptionsStruct.new
    struct[:flags] = @flags
    struct[:strict_mode] = -1
    struct[:max_depth] = 0
    struct[:recover] = @recover ? 1 : 0
    struct
  end
end
