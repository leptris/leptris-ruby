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
  Event = Struct.new(:type, :name, :text, :attrs, keyword_init: true)

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
        type: type,
        name: name_ptr.null? ? nil : name_ptr.read_string.force_encoding(Encoding::UTF_8),
        text: text_ptr.null? ? nil : text_ptr.read_string.force_encoding(Encoding::UTF_8),
        attrs: attrs
      )
    end

    private

    def capture_attrs
      count = Leptris::XML::FFI.leptris_pull_attr_count(@handle)
      return nil if count.zero?
      hash = {}
      i = 0
      while i < count
        hash[Leptris::XML::FFI.leptris_pull_attr_name(@handle, i)] =
          Leptris::XML::FFI.leptris_pull_attr_value(@handle, i)
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
