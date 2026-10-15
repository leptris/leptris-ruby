# frozen_string_literal: true

require "ffi"
require "pathname"
require "stringio"

class Leptris::XML::SAX::Parser
  CHUNK_SIZE = 4096
  private_constant :CHUNK_SIZE

  attr_reader :document, :encoding

  # streaming: true (default, since 1.9.40) delivers through the
  # engine transports — bulk/callback picked by override weight
  # (leptris-ruby#95's attribute corruption is fixed upstream in
  # libleptris 1.9.18, verified on the issue fixture). streaming:
  # false delivers from a DOM parse (SAX::DomDispatch) — the
  # correctness-first fallback kept for engines older than 1.9.18
  # and for consumers wanting the DOM view's shapes.
  def initialize(handler = Leptris::XML::SAX::Document.new,
                 encoding = nil, streaming: true, options: nil)
    @document = handler
    @encoding = encoding
    @streaming = streaming
    @skip_flags = Leptris::XML::ParseOptions.stream_flags(options)
  end

  # Door A opt-outs (1.9.283, #1459) applied before the first
  # feed on the IO path — set once, not thread-safe per the C
  # contract.
  def skip_flags=(flags)
    @skip_flags = flags.to_i & (Leptris::XML::ParseOptions::SKIP_DUP_DETECTION |
                                Leptris::XML::ParseOptions::SKIP_SOURCE_POSITIONS)
  end

  # Swapping the handler invalidates the memoized callback struct so
  # the next parse dispatches to the new handler.
  def document=(handler)
    @document = handler
    @handler_struct = nil
    @dispatched_kinds = nil
  end

  # The handler struct (eleven FFI::Function callbacks + the C
  # struct) is built once per handler and reused across parses; the
  # memoized struct is anchored against GC by the instance itself.
  def handler_struct
    @handler_struct ||= build_handler_struct
  end

  # Parse a string, IO, or file path. Dispatches to parse_memory /
  # parse_io / parse_file based on the argument type.
  def parse(input)
    case input
    when String                then parse_memory(input)
    when IO, StringIO, Pathname then parse_io(input)
    else
      raise ArgumentError, "SAX parser expects a String or IO, got #{input.class}"
    end
  end

  def parse_memory(string)
    # Only re-encode when the input is not already UTF-8 — a
    # dup+force_encoding on a multi-MB document is a full copy
    # before any parse work starts.
    unless string.encoding == Encoding::UTF_8 && string.valid_encoding?
      string = string.dup.force_encoding(Encoding::UTF_8)
    end
    unless @streaming
      Leptris::XML::SAX::DomDispatch.parse(
        @document, dispatched_kinds, string)
      return self
    end
    if native_fast?
      rc = Leptris::XML::Native.sax_parse(
        @document, native_kinds_mask, string)
      if rc != 0
        raise Leptris::XML::ParseError,
          "leptris_sax_parse failed (rc=#{rc})"
      end
    else
      handler_struct = self.handler_struct
      rc = Leptris::XML::FFI.leptris_sax_parse(
        string, string.bytesize, handler_struct.pointer, nil)
      if rc != 0
        raise Leptris::XML::ParseError,
          "leptris_sax_parse failed (rc=#{rc})"
      end
    end
    self
  end

  def parse_io(io)
    unless @streaming
      parse_memory(io.read)
      return self
    end
    if native_fast?
      parser = Leptris::XML::Native.sax_parser_create(
        @document, native_kinds_mask)
      if parser.nil?
        raise Leptris::XML::Error, "leptris_sax_parser_create failed"
      end
      begin
        Leptris::XML::Native.sax_parser_set_skip_flags(
          parser, @skip_flags || 0)
        while (chunk = io.read(CHUNK_SIZE))
          rc = Leptris::XML::Native.sax_parser_feed(parser, chunk, false)
          if rc != 0
            raise Leptris::XML::ParseError,
              "leptris_sax_parser_feed failed (rc=#{rc})"
          end
        end
        rc = Leptris::XML::Native.sax_parser_feed(parser, "", true)
        if rc != 0
          raise Leptris::XML::ParseError,
            "leptris_sax_parser_feed (final) failed (rc=#{rc})"
        end
      ensure
        Leptris::XML::Native.sax_parser_free(parser)
      end
      return self
    end
    handler_struct = self.handler_struct
    parser_ptr = Leptris::XML::FFI.leptris_sax_parser_create(
      handler_struct.pointer, nil)
    if parser_ptr.null?
      raise Leptris::XML::Error, "leptris_sax_parser_create failed"
    end
    if @skip_flags
      Leptris::XML::FFI.leptris_sax_parser_set_skip_flags(
        parser_ptr, @skip_flags)
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
    if @streaming
      File.open(path, "r") { |f| parse_io(f) }
    else
      parse_memory(File.read(path))
    end
  end

  # The handler's overridden-kind map — memoized with the handler
  # struct; document= invalidates both. The native transport derives
  # its kind bitmask from it; the FFI fallback builds its callback
  # struct from the same decisions.
  def dispatched_kinds
    @dispatched_kinds ||= begin
      kinds = {}
      {
        start_document: :start_document,
        end_document: :end_document,
        start_element: :start_element,
        end_element: :end_element,
        characters: :characters,
        comment: :comment,
        cdata_block: :cdata,
        processing_instruction: :pi,
        start_prefix_mapping: :start_prefix,
        end_prefix_mapping: :end_prefix,
        error: :error,
      }.each do |method_name, kind|
        next unless overridden?(method_name)
        kinds[kind] =
          if method_name == :start_element &&
              @document.method(:start_element).arity == 1
            :one_arg
          else
            true
          end
      end
      kinds
    end
  end

  private

  def native_fast?
    defined?(Leptris::XML::NATIVE_FAST)
  end

  # The C transport's kind bitmask — the same decisions
  # dispatched_kinds makes, in bit form. start_element's arity picks
  # the 1-arg or 2-arg dispatch; only overridden kinds attach (the
  # engine skips NULL callbacks, so cost scales with declared
  # interest, not with the document's event mix).
  NATIVE_KIND_BITS = {
    start_document: 1 << 0,
    end_document: 1 << 1,
    end_element: 1 << 4,
    characters: 1 << 5,
    comment: 1 << 6,
    cdata: 1 << 7,
    pi: 1 << 8,
    start_prefix: 1 << 9,
    end_prefix: 1 << 10,
    error: 1 << 11,
  }.freeze
  private_constant :NATIVE_KIND_BITS

  def native_kinds_mask
    mask = 0
    dispatched_kinds.each do |kind, mode|
      if kind == :start_element
        mask |= (mode == :one_arg ? (1 << 2) : (1 << 3))
      else
        mask |= NATIVE_KIND_BITS.fetch(kind, 0)
      end
    end
    mask
  end

  # Build a LeptrisSAXHandler struct populated with FFI::Function callbacks
  # that dispatch to the Ruby handler. Only the callbacks the handler
  # actually overrides are attached: the C engine skips NULL callbacks,
  # so cost scales with the handler's declared interest, not with the
  # document's event mix (measured 4.9x for an elements-only handler on
  # a 1.9 MB stream).
  def build_handler_struct
    s = Leptris::XML::FFI::SAXHandler.new
    handler = @document  # capture in closures

    if overridden?(:start_document)
      s[:start_document] = callback(:void, [:pointer]) do |_|
        handler.start_document
      end
    end

    if overridden?(:end_document)
      s[:end_document] = callback(:void, [:pointer]) do |_|
        handler.end_document
      end
    end

    if overridden?(:start_element)
      # Arity-declared interest: a start_element that takes exactly
      # one argument declares name-only — the attr walk (2N pointer
      # reads + N string pairs per start; 3.7x of an elements-only
      # parse on the 1.9 MB stream) never runs. It is also the only
      # way a 1-arg handler can receive events: the two-argument
      # call raises ArgumentError.
      if @document.method(:start_element).arity == 1
        s[:start_element] = callback(:void, [:pointer, :string, :pointer]) do |_, name, _|
          handler.start_element(utf8(name))
        end
      else
        s[:start_element] = callback(:void, [:pointer, :string, :pointer]) do |_, name, attrs_ptr|
          attrs = walk_attr_array(attrs_ptr)
          handler.start_element(utf8(name), attrs)
        end
      end
    end

    if overridden?(:end_element)
      s[:end_element] = callback(:void, [:pointer, :string]) do |_, name|
        handler.end_element(utf8(name))
      end
    end

    if overridden?(:characters)
      s[:characters] = callback(:void, [:pointer, :pointer, :size_t]) do |_, text_ptr, len|
        handler.characters(text_ptr.read_bytes(len).force_encoding(Encoding::UTF_8))
      end
    end

    if overridden?(:comment)
      s[:comment] = callback(:void, [:pointer, :string]) do |_, comment|
        handler.comment(utf8(comment))
      end
    end

    if overridden?(:cdata_block)
      s[:cdata] = callback(:void, [:pointer, :string]) do |_, cdata|
        handler.cdata_block(utf8(cdata))
      end
    end

    if overridden?(:processing_instruction)
      s[:processing_instruction] = callback(:void, [:pointer, :string, :string]) do |_, target, data|
        handler.processing_instruction(
          utf8(target), Leptris::XML::FFI.read_pi_data(utf8(data)))
      end
    end

    if overridden?(:start_prefix_mapping)
      s[:start_prefix_mapping] = callback(:void, [:pointer, :string, :string]) do |_, prefix, uri|
        handler.start_prefix_mapping(utf8(prefix), utf8(uri))
      end
    end

    if overridden?(:end_prefix_mapping)
      s[:end_prefix_mapping] = callback(:void, [:pointer, :string]) do |_, prefix|
        handler.end_prefix_mapping(utf8(prefix))
      end
    end

    if overridden?(:error)
      s[:error] = callback(:void, [:pointer, :string, :int, :int]) do |_, msg, line, col|
        handler.error(utf8(msg), line, col)
      end
    end

    s
  end

  # True when the handler defines the event method beyond the no-op
  # every SAX::Document carries — subclasses, included modules, and
  # duck-typed handlers all qualify; a handler that overrides nothing
  # attaches nothing and the parse runs at the C floor.
  def overridden?(name)
    @document.method(name).owner != Leptris::XML::SAX::Document
  rescue NameError
    false
  end

  def callback(return_type, params, blocking: true, &block)
    ::FFI::Function.new(return_type, params, blocking: blocking, &block)
  end

  # FFI's implicit :string conversion does not set encoding — every
  # callback string param crosses the seam as ASCII-8BIT unless
  # corrected here (the headers contract UTF-8; nil for NULL).
  def utf8(str)
    str.nil? ? nil : str.force_encoding(Encoding::UTF_8)
  end

  # The C `const char** attrs` is a NULL-terminated flat array of
  # name/value pairs. Build the [name, value] pairs in one pass —
  # no intermediate flat string array, no each_slice enumerator.
  def walk_attr_array(attrs_ptr)
    ptr_size = ::FFI.type_size(:pointer)
    pairs = []
    i = 0
    loop do
      name_ptr = attrs_ptr.get_pointer(i * ptr_size)
      break if name_ptr.null?
      value_ptr = attrs_ptr.get_pointer((i + 1) * ptr_size)
      pairs << [utf8(name_ptr.read_string), utf8(value_ptr.read_string)]
      i += 2
    end
    pairs
  end
end
