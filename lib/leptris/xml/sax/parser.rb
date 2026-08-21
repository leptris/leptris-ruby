# frozen_string_literal: true

require "ffi"

class Leptris::XML::SAX::Parser
  CHUNK_SIZE = 4096
  private_constant :CHUNK_SIZE

  attr_accessor :document, :encoding

  def initialize(handler = Leptris::XML::SAX::Document.new, encoding = nil)
    @document = handler
    @encoding = encoding
  end

  # Parse a string, IO, or file path. Dispatches to parse_memory /
  # parse_io / parse_file based on the argument type.
  def parse(input)
    case input
    when String                then parse_memory(input)
    when ->(x) { x.respond_to?(:read) } then parse_io(input)
    else
      raise ArgumentError, "SAX parser expects a String or IO, got #{input.class}"
    end
  end

  def parse_memory(string)
    string = string.dup.force_encoding("UTF-8")
    handler_struct = build_handler_struct
    rc = Leptris::XML::FFI.leptris_sax_parse(
      string, string.bytesize, handler_struct.pointer, nil)
    if rc != 0
      raise Leptris::XML::ParseError,
        "leptris_sax_parse failed (rc=#{rc})"
    end
    self
  end

  def parse_io(io)
    handler_struct = build_handler_struct
    parser_ptr = Leptris::XML::FFI.leptris_sax_parser_create(
      handler_struct.pointer, nil)
    if parser_ptr.null?
      raise Leptris::XML::Error, "leptris_sax_parser_create failed"
    end
    begin
      while (chunk = io.read(CHUNK_SIZE))
        rc = Leptris::XML::FFI.leptris_sax_parser_feed(
          parser_ptr, chunk, chunk.bytesize, 0)
        if rc != 0
          raise Leptris::XML::ParseError, "leptris_sax_parser_feed failed (rc=#{rc})"
        end
      end
      # Final flush
      rc = Leptris::XML::FFI.leptris_sax_parser_feed(parser_ptr, "", 0, 1)
      if rc != 0
        raise Leptris::XML::ParseError, "leptris_sax_parser_feed (final) failed (rc=#{rc})"
      end
    ensure
      Leptris::XML::FFI.leptris_sax_parser_free(parser_ptr)
    end
    self
  end

  def parse_file(path)
    File.open(path, "r") { |f| parse_io(f) }
  end

  private

  # Build a LeptrisSAXHandler struct populated with FFI::Function callbacks
  # that dispatch to the Ruby handler. The struct (and its callbacks) are
  # anchored against GC via the local variable for the duration of the
  # synchronous parse call.
  def build_handler_struct
    s = Leptris::XML::FFI::SAXHandler.new
    handler = @document  # capture in closures

    s[:start_document] = callback(:void, [:pointer]) do |_|
      handler.start_document
    end

    s[:end_document] = callback(:void, [:pointer]) do |_|
      handler.end_document
    end

    s[:start_element] = callback(:void, [:pointer, :string, :pointer]) do |_, name, attrs_ptr|
      attrs = walk_attr_array(attrs_ptr)
      handler.start_element(name, attrs)
    end

    s[:end_element] = callback(:void, [:pointer, :string]) do |_, name|
      handler.end_element(name)
    end

    s[:characters] = callback(:void, [:pointer, :pointer, :size_t]) do |_, text_ptr, len|
      handler.characters(text_ptr.read_bytes(len).force_encoding("UTF-8"))
    end

    s[:comment] = callback(:void, [:pointer, :string]) do |_, comment|
      handler.comment(comment)
    end

    s[:cdata] = callback(:void, [:pointer, :string]) do |_, cdata|
      handler.cdata_block(cdata)
    end

    s[:processing_instruction] = callback(:void, [:pointer, :string, :string]) do |_, target, data|
      handler.processing_instruction(target, data)
    end

    s[:start_prefix_mapping] = callback(:void, [:pointer, :string, :string]) do |_, prefix, uri|
      handler.start_prefix_mapping(prefix, uri)
    end

    s[:end_prefix_mapping] = callback(:void, [:pointer, :string]) do |_, prefix|
      handler.end_prefix_mapping(prefix)
    end

    s[:error] = callback(:void, [:pointer, :string, :int, :int]) do |_, msg, line, col|
      handler.error(msg, line, col)
    end

    s
  end

  def callback(return_type, params, blocking: true, &block)
    ::FFI::Function.new(return_type, params, blocking: blocking, &block)
  end

  # The C `const char** attrs` is a NULL-terminated flat array of name/value
  # pairs: [name1, value1, name2, value2, ..., NULL]. Walk into pairs.
  def walk_attr_array(attrs_ptr)
    return [] if attrs_ptr.null?
    ptr_size = ::FFI.type_size(:pointer)
    result = []
    offset = 0
    loop do
      name_ptr = attrs_ptr.get_pointer(offset)
      break if name_ptr.null?
      value_ptr = attrs_ptr.get_pointer(offset + ptr_size)
      break if value_ptr.null?
      result << [name_ptr.read_string, value_ptr.read_string]
      offset += 2 * ptr_size
    end
    result
  end
end
