# frozen_string_literal: true

require "ffi"

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
                 encoding = nil, streaming: true)
    @document = handler
    @encoding = encoding
    @streaming = streaming
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
    when ->(x) { x.respond_to?(:read) } then parse_io(input)
    else
      raise ArgumentError, "SAX parser expects a String or IO, got #{input.class}"
    end
  end

  def parse_memory(string)
    string = string.dup.force_encoding("UTF-8")
    unless @streaming
      Leptris::XML::SAX::DomDispatch.parse(
        @document, dispatched_kinds, string)
      return self
    end
    if bulk_dispatch?
      parse_memory_bulk(string)
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

  # Bulk transport for many-override handlers: record the whole
  # document C-side (~12ms per 250k events), then dispatch through
  # the recorder's drain — 250k ffi callback trampolines cost
  # ~150ms, so this wins outright for handlers that consume most of
  # the event stream (and beats Nokogiri's C extension on the same
  # shape). The delivered call shapes are IDENTICAL to the callback
  # transport (pairs arrays, arity dispatch, UTF-8, PI-data
  # normalization) — the transports are interchangeable to the
  # handler.
  #
  # Transport choice, from the round-XXVI crossover measurements:
  # ONE overridden hot kind pays less through the callbacks (the
  # engine skips C-side emission for unattached kinds entirely:
  # text-only 23ms vs 43ms), while two or more hot kinds win through
  # the recorder (start+chars 138 -> 99ms, start+end+chars 167 ->
  # 122ms vs Nokogiri's 142ms). The weights are document-shape
  # priors — text-heavy documents with tagged structure.
  HOT_KIND_WEIGHTS = {
    characters: 0.6, start_element: 0.2, end_element: 0.2,
  }.freeze
  private_constant :HOT_KIND_WEIGHTS
  DISPATCH_WEIGHT_THRESHOLD = 0.8
  private_constant :DISPATCH_WEIGHT_THRESHOLD

  def parse_memory_bulk(string)
    recorder = Leptris::XML::SAX::Recorder.open
    begin
      rc = recorder.feed(string, final: true)
      recorder.dispatch(@document, dispatched_kinds)
      if rc != 0
        raise Leptris::XML::ParseError,
          "leptris_sax_parse failed (rc=#{rc})"
      end
    ensure
      recorder.free
    end
    self
  end

  # The handler's overridden-kind map — the same decisions
  # build_handler_struct makes, in dispatch form. Memoized with the
  # handler struct; document= invalidates both.
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

  def bulk_dispatch?
    dispatched_kinds.keys.sum do |kind|
      HOT_KIND_WEIGHTS.fetch(kind, 0.0)
    end >= DISPATCH_WEIGHT_THRESHOLD
  end

  def parse_io(io)
    unless @streaming
      parse_memory(io.read)
      return self
    end
    handler_struct = self.handler_struct
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
    if @streaming
      File.open(path, "r") { |f| parse_io(f) }
    else
      parse_memory(File.read(path))
    end
  end

  private

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
