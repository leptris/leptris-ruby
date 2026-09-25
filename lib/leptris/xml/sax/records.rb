# frozen_string_literal: true

# Bulk SAX records (leptris#1298, engine leptris_sax_records_parse,
# 1.9.223+): ONE crossing drains the whole document into a flat
# record table — elements and text runs in document order, the tree
# as parent/next-sibling record indices, attributes an index range
# into a flat table, every string an (off,len) view into one
# NUL-padded buffer. The engine mints zero per-event strings; hosts
# materialize only what they consume (name/value String = one
# get_string each).
#
# Coverage: the interleaved lane's scannable subset — elements, text,
# attributes; well-formed entity-free documents without comments/
# PIs/CDATA/DOCTYPE/xmlns. Outside the subset .open answers nil
# (LEPTRIS_ERROR_NOT_SUPPORTED, zero allocation) and callers fall
# back to the callback Recorder; correctness is bit-identical.
#
# Field columns materialize once per drain via
# Pointer#read_array_of_uint32 (no Ruby object per record); the
# self_closing flag rides a separate uint8 column because it shares
# its struct tail with padding.
class Leptris::XML::SAX::Records
  KIND_ELEMENT = Leptris::XML::FFI::SAX_REC_ELEMENT
  KIND_TEXT = Leptris::XML::FFI::SAX_REC_TEXT

  REC = Leptris::XML::FFI::SaxRecord
  ATTR = Leptris::XML::FFI::SaxAttr
  REC_U32 = REC.size / 4
  ATTR_U32 = ATTR.size / 4

  attr_reader :count, :attr_count

  # Drains xml into a table. Returns nil unless the document drained
  # cleanly — outside the scannable subset (NOT_SUPPORTED, zero
  # allocation) OR malformed (the callback path reports parse errors
  # with position) — callers fall back to the callback Recorder in
  # every nil case; correctness is bit-identical.
  def self.open(xml)
    xml = xml.to_s
    out = ::FFI::MemoryPointer.new(:pointer)
    status = Leptris::XML::FFI.leptris_sax_records_parse(
      xml, xml.bytesize, 0, out
    )
    return nil unless status == Leptris::XML::FFI::LEPTRIS_OK

    new(out.read_pointer)
  end

  # Block form: the table dies at the end of the block — every view
  # dies with it, so materialize inside.
  def self.parse(xml)
    table = open(xml)
    return nil unless table

    begin
      yield table
    ensure
      table.free
    end
  end

  def initialize(ptr)
    @ptr = ptr
    @count = Leptris::XML::FFI.leptris_sax_records_count(@ptr)
    recs = Leptris::XML::FFI.leptris_sax_records_data(@ptr)
    attr_out = ::FFI::MemoryPointer.new(:pointer)
    attrs = Leptris::XML::FFI.leptris_sax_records_attrs(@ptr, attr_out)
    @attr_count = attr_out.read_uint64
    @buf = Leptris::XML::FFI.leptris_sax_records_buffer(@ptr)
    # Whole-table single reads: no Ruby object per record. The u32
    # columns stride by struct size; the flags (self_closing /
    # value_has_ws) are u8 tails read per-byte off their layout
    # offset — endian-safe.
    @rec_u32 = recs.read_array_of_uint32(@count * REC_U32)
    @rec_flag = recs.read_array_of_uint8(@count * REC.size)
    @attr_u32 = attrs.read_array_of_uint32(@attr_count * ATTR_U32)
    @attr_flag = attrs.read_array_of_uint8(@attr_count * ATTR.size)
    @rec_flag_off = REC.offset_of(:self_closing)
    @attr_flag_off = ATTR.offset_of(:value_has_ws)
  end

  def free
    return if @ptr.nil?

    Leptris::XML::FFI.leptris_sax_records_free(@ptr)
    @ptr = nil
  end

  def kind(i)
    @rec_u32[i * REC_U32]
  end

  # Parent record index (0xFFFFFFFF for document-level records).
  def parent(i)
    @rec_u32[i * REC_U32 + 1]
  end

  # Element name or text content — ONE String per call, UTF-8.
  def view(i)
    base = i * REC_U32
    @buf.get_string(@rec_u32[base + 3], @rec_u32[base + 4])
        .force_encoding(Encoding::UTF_8)
  end

  def self_closing?(i)
    @rec_flag[i * REC.size + @rec_flag_off] != 0
  end

  def attr_first(i)
    @rec_u32[i * REC_U32 + 8]
  end

  def attr_count_of(i)
    @rec_u32[i * REC_U32 + 9]
  end

  def attr_name(k)
    @buf.get_string(@attr_u32[k * ATTR_U32],
                    @attr_u32[k * ATTR_U32 + 1])
        .force_encoding(Encoding::UTF_8)
  end

  def attr_value(k)
    @buf.get_string(@attr_u32[k * ATTR_U32 + 2],
                    @attr_u32[k * ATTR_U32 + 3])
        .force_encoding(Encoding::UTF_8)
  end

  # Literal \t/\n/\r in the raw value — the consumer applies
  # XML 1.0 §3.3.3 (map each break byte to a space).
  def attr_value_has_ws?(k)
    @attr_flag[k * ATTR.size + @attr_flag_off] != 0
  end
end
