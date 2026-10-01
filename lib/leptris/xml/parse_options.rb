# frozen_string_literal: true

# Parser flags, mirroring LeptrisParseFlags in libleptris's public
# headers. Pass an instance as `Leptris::XML.parse(xml, options:)`.
class Leptris::XML::ParseOptions
  # Discard whitespace-only text nodes (runs between tags that contain
  # nothing but spaces/tabs/newlines). Matches libxml2's
  # XML_PARSE_NOBLANKS and Nokogiri's noblanks. Documents parsed this
  # way do not round-trip pretty-printed formatting byte-for-byte.
  NOBLANKS = Leptris::XML::FFI::LEPTRIS_PARSE_DROP_WS_TEXT

  # Apply DTD ATTLIST default (and #FIXED) attribute values at parse
  # time (libleptris >= 1.9.8, leptris/leptris#606). Matches libxml2's
  # XML_PARSE_DTDATTR and Nokogiri's dtdload+dtdattr semantics. Off by
  # default: the ecosystem compares against libxml2's no-DTDATTR
  # default, and W3C C14N 1.1 example 3.3's canonical form excludes
  # defaulted attributes.
  DTDATTR = Leptris::XML::FFI::LEPTRIS_PARSE_DTDATTR

  # Keep &name; entity references unexpanded as first-class
  # EntityReference nodes (libleptris 1.9.176, upstream #1094 /
  # leptris-ruby#212): text runs split around them, character
  # references still expand, and the references serialize back
  # verbatim.
  KEEP_ENTITY_REFS = Leptris::XML::FFI::LEPTRIS_PARSE_KEEP_ENTITY_REFS

  # Skip duplicate-attribute detection at parse time (libleptris
  # 1.9.272, Lane-18 round 18 Door A): duplicate attributes are
  # admitted silently — first wins for queries, no recover diag.
  # For sources that cannot carry duplicates. Off by default.
  SKIP_DUP_DETECTION = Leptris::XML::FFI::LEPTRIS_PARSE_SKIP_DUP_DETECTION

  # Skip source-position bookkeeping (libleptris 1.9.272, Door A):
  # element source columns degrade to zeros (line still resolves
  # from the buffer). For consumers that never read positions.
  # Off by default.
  SKIP_SOURCE_POSITIONS =
    Leptris::XML::FFI::LEPTRIS_PARSE_SKIP_SOURCE_POSITIONS

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

  def self.keep_entity_refs
    new(KEEP_ENTITY_REFS)
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

  def self.dtdattr
    new(DTDATTR)
  end

  # Streaming-path resolver (1.9.283, #1459): the iterparse / pull /
  # recorder / SAX-IO faces consume exactly the two Door A opt-out
  # bits — everything else on a ParseOptions is DOM-parse surface.
  # Returns nil when no opt-out is set, so the flagless C twins
  # keep their zero-flag default byte-parity.
  def self.stream_flags(options)
    return nil unless options
    unless options.is_a?(Leptris::XML::ParseOptions)
      raise ArgumentError, "options must be a Leptris::XML::ParseOptions"
    end

    mask = SKIP_DUP_DETECTION | SKIP_SOURCE_POSITIONS
    flags = options.flags & mask
    flags.zero? ? nil : flags
  end
  def self.skip_dup_detection
    new(SKIP_DUP_DETECTION)
  end

  def self.skip_source_positions
    new(SKIP_SOURCE_POSITIONS)
  end

  def dtdattr?
    @flags & DTDATTR != 0
  end

  def keep_entity_refs?
    @flags & KEEP_ENTITY_REFS != 0
  end

  def skip_dup_detection?
    @flags & SKIP_DUP_DETECTION != 0
  end

  def skip_source_positions?
    @flags & SKIP_SOURCE_POSITIONS != 0
  end

  def dtdattr=(value)
    if value then @flags |= DTDATTR else @flags &= ~DTDATTR end
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
