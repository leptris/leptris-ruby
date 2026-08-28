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

  # Kind symbol per code byte — Array indexing in the drain loop,
  # not a Hash lookup per event.
  KIND_BY_CODE = Array.new(KINDS.size) { |code| KINDS[code] }.freeze

  def self.open
    raw = Leptris::XML::FFI.leptris_sax_recorder_new
    if raw.null?
      raise Leptris::XML::Error, "leptris_sax_recorder_new failed"
    end
    new(raw)
  end

  # One-shot parse over a complete document, yielding Record structs.
  # +kinds+ filters the drain (see #each_event) — pass e.g.
  # `kinds: [:start_element]` to slice strings only for the events
  # you consume.
  def self.parse(xml_or_io, kinds: nil)
    recorder = open
    begin
      if xml_or_io.respond_to?(:read)
        recorder.feed_stream(xml_or_io, kinds: kinds) { |*args| yield(*args) }
      else
        recorder.feed(xml_or_io.to_s, final: true)
        recorder.each_event(*Array(kinds)) { |*args| yield(*args) }
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
  def feed_stream(io, chunk_size = 65_536, kinds: nil, &block)
    while (chunk = io.read(chunk_size))
      feed(chunk)
      each_event(*Array(kinds), &block)
    end
    feed("", final: true)
    each_event(*Array(kinds), &block)
  end

  # Which kinds carry each string field (the record layout leaves
  # the other at offset 0 / length 0): slicing a zero-length run
  # allocates a wasted empty String per event — 150k+ of them on a
  # text-heavy document. Unused fields yield nil (the callback
  # transport delivers no name for characters either).
  HAS_NAME = {
    start_element: true, end_element: true,
    pi: true, start_prefix: true, end_prefix: true,
  }.freeze
  HAS_TEXT = {
    characters: true, comment: true, cdata: true,
    pi: true, start_prefix: true, error: true,
  }.freeze

  # Layout offsets (the struct stays the ABI's single source of
  # truth) and per-count kind-strip templates: one byte per record,
  # skipping the stride — the kind codes are 0..10, so the strip
  # unpacks to cache-resident Fixnums, unlike the old whole-record
  # unpack whose 2.25M-Integer array for a single-feed drain was
  # most of the loop's allocation profile.
  RECORD = Leptris::XML::FFI::SaxEventRecord
  NAME_OFF = RECORD.offset_of(:name_off)
  NAME_LEN = RECORD.offset_of(:name_len)
  TEXT_OFF = RECORD.offset_of(:text_off)
  TEXT_LEN = RECORD.offset_of(:text_len)
  ATTRS_OFF = RECORD.offset_of(:attrs_off)
  ATTR_COUNT = RECORD.offset_of(:attr_count)
  LINE_OFF = RECORD.offset_of(:line)
  COLUMN_OFF = RECORD.offset_of(:column)
  RECORD_STRIDE = RECORD.size
  SAX_EVENT_CHARACTERS_CODE = Leptris::XML::FFI::SAX_EVENT_CHARACTERS
  NUL = "\0".freeze
  KIND_TEMPLATE_FOR = ::Hash.new do |cache, count|
    cache[count] = ("C x#{RECORD_STRIDE - 1}" * count)
  end

  # Dispatch drain: delivers the recorded events as handler method
  # calls with the CALLBACK transport's exact shapes — pairs arrays
  # (not hashes), one-argument start_element arity dispatch, UTF-8
  # strings, PI-data whitespace normalization. +dispatched+ maps
  # kind symbols to true for the kinds the handler overrides (the
  # attach-only-overridden policy carried onto the bulk transport:
  # other records cost one strip read). The C recorder costs ~12ms
  # per 250k-event document while 250k ffi callback trampolines
  # cost ~150ms — this is how a many-override handler beats the
  # callback transport (and Nokogiri's C extension) outright.
  def dispatch(handler, dispatched)
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
      records = records_ptr.read_bytes(count * RECORD_STRIDE)
      kinds = records.unpack(KIND_TEMPLATE_FOR[count])

      one_arg_start = dispatched[:start_element] == :one_arg
      i = 0
      while i < count
        code = kinds[i]
        kind = KIND_BY_CODE[code]
        if kind && dispatched[kind]
          base = i * RECORD_STRIDE
          case kind
          when :characters
            handler.characters(slice(arena,
              records_ptr.get_uint32(base + TEXT_OFF),
              records_ptr.get_uint32(base + TEXT_LEN)))
          when :start_element
            name = slice(arena,
              records_ptr.get_uint32(base + NAME_OFF),
              records_ptr.get_uint32(base + NAME_LEN))
            if one_arg_start
              handler.start_element(name)
            else
              handler.start_element(name, attrs_pairs(arena,
                records_ptr.get_uint32(base + ATTRS_OFF),
                records_ptr.get_uint32(base + ATTR_COUNT)))
            end
          when :end_element
            handler.end_element(slice(arena,
              records_ptr.get_uint32(base + NAME_OFF),
              records_ptr.get_uint32(base + NAME_LEN)))
          when :comment
            handler.comment(slice(arena,
              records_ptr.get_uint32(base + TEXT_OFF),
              records_ptr.get_uint32(base + TEXT_LEN)))
          when :cdata
            handler.cdata_block(slice(arena,
              records_ptr.get_uint32(base + TEXT_OFF),
              records_ptr.get_uint32(base + TEXT_LEN)))
          when :pi
            handler.processing_instruction(slice(arena,
              records_ptr.get_uint32(base + NAME_OFF),
              records_ptr.get_uint32(base + NAME_LEN)),
              Leptris::XML::FFI.read_pi_data(slice(arena,
                records_ptr.get_uint32(base + TEXT_OFF),
                records_ptr.get_uint32(base + TEXT_LEN))))
          when :start_prefix
            handler.start_prefix_mapping(slice(arena,
              records_ptr.get_uint32(base + NAME_OFF),
              records_ptr.get_uint32(base + NAME_LEN)),
              slice(arena,
                records_ptr.get_uint32(base + TEXT_OFF),
                records_ptr.get_uint32(base + TEXT_LEN)))
          when :end_prefix
            handler.end_prefix_mapping(slice(arena,
              records_ptr.get_uint32(base + NAME_OFF),
              records_ptr.get_uint32(base + NAME_LEN)))
          when :error
            handler.error(slice(arena,
              records_ptr.get_uint32(base + TEXT_OFF),
              records_ptr.get_uint32(base + TEXT_LEN)),
              records_ptr.get_uint32(base + LINE_OFF),
              records_ptr.get_uint32(base + COLUMN_OFF))
          when :start_document
            handler.start_document
          when :end_document
            handler.end_document
          end
        end
        i += 1
      end
    ensure
      count_ptr.free
      len_ptr.free
    end
    self
  end

  # attrs as [name, value] pairs in source order — the callback
  # transport's shape (walk_attr_array).
  def attrs_pairs(arena, off, count)
    return [] if count.zero?
    pairs = []
    pos = off
    nul = NUL
    utf8 = Encoding::UTF_8
    while count > 0
      name_end = arena.index(nul, pos)
      name = arena.byteslice(pos, name_end - pos).force_encoding(utf8)
      pos = name_end + 1
      value_end = arena.index(nul, pos)
      pairs << [name,
        arena.byteslice(pos, value_end - pos).force_encoding(utf8)]
      pos = value_end + 1
      count -= 1
    end
    pairs
  end

  # Drains the current chunk's records: bulk-reads the record array
  # and the packed arena (two FFI calls), then slices every string
  # from the arena in Ruby — no per-string FFI. With +kinds+, records
  # of other kinds are skipped BEFORE any string is sliced: an
  # unwanted event costs one Array read, and cost scales with what
  # the consumer asked for, not with the document's event mix.
  def each_event(*kinds)
    wanted = kinds.empty? ? nil : wanted_set(kinds)
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

      # Two-level drain: ONE bulk read + kind-strip unpack decides
      # which records to touch, then each yielded event's fields are
      # read individually (get_uint32 at layout offsets) — an
      # unwanted record costs one strip read, an unused FIELD costs
      # nothing, and no per-chunk field array is ever built.
      records = records_ptr.read_bytes(count * RECORD_STRIDE)
      kinds = records.unpack(KIND_TEMPLATE_FOR[count])

      has_name = HAS_NAME
      has_text = HAS_TEXT
      drain = wanted.nil?
      i = 0
      while i < count
        code = kinds[i]
        base = i * RECORD_STRIDE
        if code == SAX_EVENT_CHARACTERS_CODE && drain
          # The dominant branch (text-heavy documents): no name, no
          # attrs, no per-kind gate lookups — kind, text, position.
          yield :characters, nil,
                slice(arena, records_ptr.get_uint32(base + TEXT_OFF),
                             records_ptr.get_uint32(base + TEXT_LEN)),
                nil,
                records_ptr.get_uint32(base + LINE_OFF),
                records_ptr.get_uint32(base + COLUMN_OFF)
        else
          kind = KIND_BY_CODE[code]
          if kind && (drain || wanted[kind])
            name = if has_name[kind]
                     slice(arena, records_ptr.get_uint32(base + NAME_OFF),
                                  records_ptr.get_uint32(base + NAME_LEN))
                   end
            text = if has_text[kind]
                     slice(arena, records_ptr.get_uint32(base + TEXT_OFF),
                                  records_ptr.get_uint32(base + TEXT_LEN))
                   end
            text = Leptris::XML::FFI.read_pi_data(text) if kind == :pi
            yield kind, name, text,
                  attrs_from(arena, records_ptr.get_uint32(base + ATTRS_OFF),
                                    records_ptr.get_uint32(base + ATTR_COUNT)),
                  records_ptr.get_uint32(base + LINE_OFF),
                  records_ptr.get_uint32(base + COLUMN_OFF)
          end
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

  def wanted_set(kinds)
    unknown = kinds.each_with_object([]) do |kind, acc|
      acc << kind unless KINDS.value?(kind)
    end
    unless unknown.empty?
      raise ArgumentError,
        "unknown event kinds #{unknown.inspect} " \
        "(known: #{KINDS.values.inspect})"
    end
    kinds.each_with_object({}) { |kind, set| set[kind] = true }
  end

  # The default-namespace prefix is legitimately "" (START_PREFIX:
  # name may be zero-length) — zero-length slices stay "" where the
  # field is carried (unused fields never reach here).
  def slice(arena, off, len)
    arena.byteslice(off, len).force_encoding(Encoding::UTF_8)
  end

  # attrs_off addresses name\0value\0... pairs, attr_count pairs;
  # nil when the element carries none.
  def attrs_from(arena, off, count)
    return nil if count.zero?
    hash = {}
    pos = off
    nul = NUL
    utf8 = Encoding::UTF_8
    while count > 0
      name_end = arena.index(nul, pos)
      name = arena.byteslice(pos, name_end - pos).force_encoding(utf8)
      pos = name_end + 1
      value_end = arena.index(nul, pos)
      hash[name] =
        arena.byteslice(pos, value_end - pos).force_encoding(utf8)
      pos = value_end + 1
      count -= 1
    end
    hash
  end
end
