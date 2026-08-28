# frozen_string_literal: true

require "ffi"

# Pull parsing (libleptris v1.6.0): a StAX-style cursor over a
# document. Each #next advances one event; attributes are readable
# only during the start_element event just returned.
#
#     Leptris::XML::Pull.parse(xml).each do |event|
#       case event.type
#       when :start_element then handle(event.name, event.attrs)
#       when :text then handle(event.text)
#       end
#     end
#
module Leptris::XML::Pull
  # Constructed positionally by the parser: the keyword-init
  # variant cost ~220ns/event in batch drains (round XXI). Readers
  # (event.type, event.attrs, ...) are unchanged.
  Event = Struct.new(:type, :name, :text, :attrs)

  TYPES = {
    Leptris::XML::FFI::PULL_START_ELEMENT => :start_element,
    Leptris::XML::FFI::PULL_END_ELEMENT => :end_element,
    Leptris::XML::FFI::PULL_TEXT => :text,
    Leptris::XML::FFI::PULL_COMMENT => :comment,
    Leptris::XML::FFI::PULL_CDATA => :cdata,
    Leptris::XML::FFI::PULL_PI => :pi,
    Leptris::XML::FFI::PULL_END_DOCUMENT => :end_document,
    Leptris::XML::FFI::PULL_ERROR => :error,
  }.freeze

  class Parser
    def self.parse(xml_or_io)
      xml = xml_or_io.respond_to?(:read) ? xml_or_io.read : xml_or_io.to_s
      new(Leptris::XML::FFI.leptris_pull_new(xml, xml.bytesize))
    end

    def self.parse_file(path)
      new(Leptris::XML::FFI.leptris_pull_new_file(path))
    end

    def initialize(handle)
      raise Leptris::XML::ParseError, "leptris_pull_new failed" if handle.null?
      @handle = handle
    end

    # Releases the C parser. Safe to call twice.
    def free
      return if @handle.nil?
      Leptris::XML::FFI.leptris_pull_free(@handle)
      @handle = nil
    end

    def each
      return enum_for(:each) unless block_given?
      loop do
        event = next_event
        break if event.nil?
        yield event
        break if event.type == :end_document || event.type == :error
      end
      self
    end

    # Bulk-delivers events (libleptris 1.9.7, upstream #589): ONE C
    # call stages up to +max_count+ events — the per-event dispatch
    # that made streaming ~145x slower than a DOM parse collapses to
    # amortized noise. Per the engine's protocol, attributes are
    # captured only for the LAST start_element of each batch
    # (earlier starts in the same batch carry nil attrs — segment
    # boundaries fall where they fall); use #each when every
    # start's attrs must be captured.
    def each_batch(max_count = 256)
      return enum_for(:each_batch, max_count) unless block_given?
      stride = Leptris::XML::FFI::PullEventStruct.size
      type_off = 0
      name_off = Leptris::XML::FFI::PullEventStruct.offset_of(:name)
      text_off = Leptris::XML::FFI::PullEventStruct.offset_of(:text)
      buffer = Leptris::XML::FFI.scratch_events(max_count)
      while (n = Leptris::XML::FFI.leptris_pull_next_batch(
               @handle, buffer, max_count)) > 0
        events = Array.new(n) do |i|
          base = i * stride
          name_ptr = buffer.get_pointer(base + name_off)
          text_ptr = buffer.get_pointer(base + text_off)
          Event.new(
            TYPES[buffer.get_int(base + type_off)],
            name_ptr.null? ? nil :
              name_ptr.read_string.force_encoding(Encoding::UTF_8),
            text_ptr.null? ? nil :
              text_ptr.read_string.force_encoding(Encoding::UTF_8),
            nil
          )
        end
        # The attr mirror holds the batch's most recent start.
        last_start = nil
        events.each_with_index do |event, i|
          last_start = i if event.type == :start_element
        end
        events[last_start].attrs = capture_attrs if last_start
        events.each { |event| yield event }
        tail = events.last.type
        break if tail == :end_document || tail == :error
      end
      self
    end

    # Hot-loop offsets: derived from PullEventStruct's layout (the
    # struct stays the single source of truth for the ABI), read via
    # get_int/get_pointer so the per-event struct-wrapper allocation
    # disappears from streaming loops.
    NAME_OFFSET = Leptris::XML::FFI::PullEventStruct.offset_of(:name)
    TEXT_OFFSET = Leptris::XML::FFI::PullEventStruct.offset_of(:text)
    private_constant :NAME_OFFSET, :TEXT_OFFSET

    # Advances the cursor and returns the next Event, or nil after the
    # end of the document. Attribute values are captured during
    # start_element because the C accessors are valid only for the
    # most recently returned event.
    def next_event
      raw = Leptris::XML::FFI.leptris_pull_next(@handle)
      return nil if raw.null?
      type = TYPES[raw.get_int(0)]
      name_ptr = raw.get_pointer(NAME_OFFSET)
      text_ptr = raw.get_pointer(TEXT_OFFSET)
      attrs = type == :start_element ? capture_attrs : nil
      Event.new(
        type,
        name_ptr.null? ? nil : name_ptr.read_string.force_encoding(Encoding::UTF_8),
        text_ptr.null? ? nil : text_ptr.read_string.force_encoding(Encoding::UTF_8),
        attrs
      )
    end

    private

    # One count-only query plus one flat copy (leptris_pull_attrs,
    # 1.9.7) — the char** wire format the SAX callbacks already use —
    # replaces the 2N per-index dispatches.
    def capture_attrs
      total = Leptris::XML::FFI.leptris_pull_attrs(@handle, nil, 0)
      return nil if total.zero?
      buffer = Leptris::XML::FFI.scratch_pointers(2 * total)
      copied = Leptris::XML::FFI.leptris_pull_attrs(@handle, buffer, total)
      ptr_size = ::FFI.type_size(:pointer)
      hash = {}
      i = 0
      while i < copied
        name = buffer.get_pointer(2 * i * ptr_size).read_string
          .force_encoding(Encoding::UTF_8)
        value = buffer.get_pointer((2 * i + 1) * ptr_size).read_string
          .force_encoding(Encoding::UTF_8)
        hash[name] = value
        i += 1
      end
      hash
    end
  end

  def self.parse(xml_or_io, &block)
    parser = Parser.parse(xml_or_io)
    if block
      begin
        parser.each(&block)
      ensure
        parser.free
      end
    else
      parser
    end
  end

  def self.parse_file(path, &block)
    parser = Parser.parse_file(path)
    if block
      begin
        parser.each(&block)
      ensure
        parser.free
      end
    else
      parser
    end
  end
end
