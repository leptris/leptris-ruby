# frozen_string_literal: true

require "ffi"

# Chunked event recorder (libleptris 1.9.4, issue #585): a SAX
# transport that buffers events C-side — fixed LeptrisSaxEventRecord
# entries plus a packed string arena — and drains them in one bulk
# read per fed chunk. The handler receives the identical calls the
# callback API makes; only the transport changes, and the callback
# count becomes O(chunks), not O(events): through FFI, per-event
# C-to-Ruby dispatch cost more than the parse itself.
#
#     Leptris::XML::SAX::Recorder.parse(xml) do |kind, name, text, attrs|
#       # kind: :start_element, :characters, ... (see KINDS)
#     end
#
class Leptris::XML::SAX::Recorder
  KINDS = {
    Leptris::XML::FFI::SAX_EVENT_START_DOCUMENT => :start_document,
    Leptris::XML::FFI::SAX_EVENT_END_DOCUMENT => :end_document,
    Leptris::XML::FFI::SAX_EVENT_START_ELEMENT => :start_element,
    Leptris::XML::FFI::SAX_EVENT_END_ELEMENT => :end_element,
    Leptris::XML::FFI::SAX_EVENT_CHARACTERS => :characters,
    Leptris::XML::FFI::SAX_EVENT_COMMENT => :comment,
    Leptris::XML::FFI::SAX_EVENT_CDATA => :cdata,
    Leptris::XML::FFI::SAX_EVENT_PI => :pi,
    Leptris::XML::FFI::SAX_EVENT_START_PREFIX => :start_prefix,
    Leptris::XML::FFI::SAX_EVENT_END_PREFIX => :end_prefix,
    Leptris::XML::FFI::SAX_EVENT_ERROR => :error,
  }.freeze

  def self.open
    raw = Leptris::XML::FFI.leptris_sax_recorder_new
    if raw.null?
      raise Leptris::XML::Error, "leptris_sax_recorder_new failed"
    end
    new(raw)
  end

  # One-shot parse over a complete document, yielding Record structs.
  def self.parse(xml_or_io)
    recorder = open
    begin
      if xml_or_io.respond_to?(:read)
        recorder.feed_stream(xml_or_io) { |*args| yield(*args) }
      else
        recorder.feed(xml_or_io.to_s, final: true)
        recorder.each_event { |*args| yield(*args) }
      end
    ensure
      recorder.free
    end
  end

  def initialize(handle)
    @handle = handle
  end

  def free
    return if @handle.nil?
    Leptris::XML::FFI.leptris_sax_recorder_free(@handle)
    @handle = nil
  end

  # Feed one chunk; records/arena reset at feed entry, so drain
  # after every feed. Returns self.
  def feed(chunk, final: false)
    chunk = chunk.dup.force_encoding(Encoding::UTF_8)
    rc = Leptris::XML::FFI.leptris_sax_recorder_feed(
      @handle, chunk, chunk.bytesize, final ? 1 : 0)
    rc
  end

  # Feed an IO in chunks, draining events after each chunk.
  def feed_stream(io, chunk_size = 65_536, &block)
    while (chunk = io.read(chunk_size))
      feed(chunk)
      each_event(&block)
    end
    feed("", final: true)
    each_event(&block)
  end

  # Drains the current chunk's records: bulk-reads the record array
  # and the packed arena (two FFI calls), then slices every string
  # from the arena in Ruby — no per-string FFI.
  def each_event
    count_ptr = ::FFI::MemoryPointer.new(:size_t)
    len_ptr = ::FFI::MemoryPointer.new(:size_t)
    begin
      records_ptr = Leptris::XML::FFI.leptris_sax_recorder_records(
        @handle, count_ptr)
      return self if records_ptr.null? || count_ptr.read_uint64.zero?

      arena_ptr = Leptris::XML::FFI.leptris_sax_recorder_arena(
        @handle, len_ptr)
      arena = arena_ptr.read_bytes(len_ptr.read_uint64)
      count = count_ptr.read_uint64

      # The whole record block in ONE read: read_bytes + String#unpack
      # (C-fast) — two FFI calls per chunk total (records + arena),
      # the true bulk discipline. Template per record: kind byte,
      # 7 pad, then the eight uint32 fields (little-endian hosts —
      # the layout the header freezes for FFI mirrors).
      stride = Leptris::XML::FFI::SaxEventRecord.size
      fields = records_ptr.read_bytes(count * stride)
        .unpack("C x7 V8" * count)

      i = 0
      while i < count
        kind = KINDS[fields[i * 9]]
        if kind
          base = i * 9 + 1
          yield kind,
                slice(arena, fields[base], fields[base + 1]),
                slice(arena, fields[base + 2], fields[base + 3]),
                attrs_from(arena, fields[base + 4], fields[base + 5]),
                fields[base + 6], fields[base + 7]
        end
        i += 1
      end
    ensure
      count_ptr.free
      len_ptr.free
    end
    self
  end

  private

  # Zero-length slices are empty strings, not nil — the default
  # namespace prefix is legitimately "" (START_PREFIX: name may be
  # ""), matching the callback transport's delivery.
  def slice(arena, off, len)
    arena.byteslice(off, len).force_encoding(Encoding::UTF_8)
  end

  # attrs_off addresses name\0value\0... pairs, attr_count pairs;
  # nil when the element carries none.
  def attrs_from(arena, off, count)
    return nil if count.zero?
    hash = {}
    pos = off
    count.times do
      name_end = arena.index("\0", pos)
      name = arena.byteslice(pos, name_end - pos)
      pos = name_end + 1
      value_end = arena.index("\0", pos)
      value = arena.byteslice(pos, value_end - pos)
      pos = value_end + 1
      hash[name.force_encoding(Encoding::UTF_8)] =
        value.force_encoding(Encoding::UTF_8)
    end
    hash
  end
end
