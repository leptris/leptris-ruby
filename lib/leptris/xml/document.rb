# frozen_string_literal: true

require "ffi"

class Leptris::XML::Document
  attr_reader :c_ptr, :wrapper_cache

  # @api private
  # Internal flag container shared between the Document instance and its
  # GC finalizer. Using a one-element Array because Procs close over
  # variables by reference — mutating freed[0] is visible from both
  # the explicit `free` path and the finalizer. This eliminates the
  # double-free that FFI::AutoPointer's release proc caused when
  # `Document#free` was called explicitly and then GC ran.
  Freed = Struct.new(:state)  # state: :alive | :freed

  def initialize(c_ptr = nil, freed = Freed.new(:alive))
    @c_ptr = c_ptr
    @freed = freed
    @readonly = false
    # Per-document STRONG cache for Node wrappers, keyed on c_ptr
    # address. Every wrapper is created through Node.wrap, which is the
    # single construction path, so the same C node always yields the
    # same Ruby object. Cleared when the Document is freed — no stale
    # entries.
    #
    # Deliberately NOT ObjectSpace::WeakMap: a weak cache makes wrapper
    # identity a GC race. `doc.root.equal?(doc.root)` failed on the
    # Windows CI matrix (188 examples, the 4 identity specs) because
    # between the two calls the first wrapper was referenced only by
    # the weak map — any GC sweep evicted it and the second call built
    # a fresh object. A strong cache costs at most one wrapper per node
    # actually visited, held until the document dies.
    @wrapper_cache = {}
  end

  def self.parse(xml_or_io, options: nil, readonly: false, recover: false)
    xml = xml_or_io.respond_to?(:read) ? xml_or_io.read : xml_or_io.to_s
    if xml.empty?
      raise Leptris::XML::ParseError, "empty input"
    end
    if options.nil?
      options = Leptris::XML::ParseOptions.new(recover: recover)
    elsif recover && !options.recover?
      options = options | Leptris::XML::ParseOptions.new(recover: true)
    elsif !options.is_a?(Leptris::XML::ParseOptions)
      raise ArgumentError, "options must be a Leptris::XML::ParseOptions"
    end
    # The status out-param is nullable; the thread-local last error
    # carries failure detail, and skipping the per-parse MemoryPointer
    # is measurable on small documents.
    raw =
      if options.struct_required?
        # Recover is a struct field, not a parse flag — the options
        # struct path (leptris_parse_string_ex) is the only carrier.
        options_struct = options.to_c_struct
        Leptris::XML::FFI.leptris_parse_string_ex(
          xml, xml.bytesize, options_struct.pointer, nil)
      elsif options.flags.zero?
        Leptris::XML::FFI.leptris_parse_string(xml, xml.bytesize, nil)
      else
        Leptris::XML::FFI.leptris_parse_string_flags(
          xml, xml.bytesize, options.flags, nil)
      end
    if raw.null?
      if options.recover?
        # Unreachable in practice: recover returns an empty document
        # rather than NULL; kept so a contract change fails loudly.
        raise Leptris::XML::Error,
          "leptris_parse_string_ex returned NULL under recover"
      end
      raise Leptris::XML::ParseError,
        "leptris_parse_string failed: " +
        Leptris::XML::FFI.leptris_last_error.to_s
    end
    wrap(raw).tap { |doc| doc.readonly! if readonly }
  end

  def self.parse_file(path, readonly: false)
    raw = Leptris::XML::FFI.leptris_parse_file(path, nil)
    if raw.null?
      raise Leptris::XML::ParseError,
        "leptris_parse_file failed: " +
        Leptris::XML::FFI.leptris_last_error.to_s
    end
    wrap(raw).tap { |doc| doc.readonly! if readonly }
  end

  # Create an empty document (no root element) backed by its own memory
  # pool. Elements for the tree are created against it via
  # #create_element and friends, then attached with #root=.
  def self.create
    raw = Leptris::XML::FFI.leptris_document_create
    raise Leptris::XML::Error,
      "leptris_document_create failed" if raw.null?
    wrap(raw)
  end

  # Convert a raw LeptrisDocument pointer into a Ruby Document with safe
  # GC lifetime management. The finalizer captures the raw address
  # integer (not the Document or Pointer object — those would prevent
  # GC) and shares a one-shot flag with the instance so explicit
  # `#free` and the GC finalizer can never both call
  # `leptris_document_free` on the same address.
  def self.wrap(raw_address)
    addr = raw_address.is_a?(::FFI::Pointer) ? raw_address.address : raw_address
    ptr = ::FFI::Pointer.new(addr)
    freed = Freed.new(:alive)
    doc = new(ptr, freed)
    ObjectSpace.define_finalizer(doc, finalizer(addr, freed))
    doc
  end

  def self.finalizer(address, freed)
    proc do
      next if freed.state == :freed
      freed.state = :freed
      Leptris::XML::FFI.leptris_document_free(::FFI::Pointer.new(address))
    end
  end
  private_class_method :finalizer

  def root
    raise Leptris::XML::UseAfterFreeError if @freed.state == :freed
    return nil if @c_ptr.nil?
    ptr = Leptris::XML::FFI.leptris_document_root(@c_ptr)
    return nil if ptr.null?
    Leptris::XML::Node.wrap(ptr, self)
  end

  # Attach +element+ as the document's root element. The element must
  # have been created against this document and must not already have
  # a parent. Any previous root is left detached (still owned by the
  # document's pool until #free).
  def root=(element)
    raise Leptris::XML::UseAfterFreeError if @freed.state == :freed
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_document_set_root(@c_ptr, element.c_ptr))
    element
  end

  def create_element(name)
    ptr = Leptris::XML::FFI.leptris_element_create(@c_ptr, name)
    raise Leptris::XML::Error, "leptris_element_create failed" if ptr.null?
    Leptris::XML::Node.wrap(ptr, self)
  end

  def create_text_node(content)
    ptr = Leptris::XML::FFI.leptris_text_node_create(@c_ptr, content.to_s)
    raise Leptris::XML::Error, "leptris_text_node_create failed" if ptr.null?
    Leptris::XML::Node.wrap(ptr, self)
  end

  def create_comment(content)
    ptr = Leptris::XML::FFI.leptris_comment_node_create(@c_ptr, content.to_s)
    raise Leptris::XML::Error, "leptris_comment_node_create failed" if ptr.null?
    Leptris::XML::Node.wrap(ptr, self)
  end

  def create_cdata(content)
    ptr = Leptris::XML::FFI.leptris_cdata_node_create(@c_ptr, content.to_s)
    raise Leptris::XML::Error, "leptris_cdata_node_create failed" if ptr.null?
    Leptris::XML::Node.wrap(ptr, self)
  end

  def create_processing_instruction(target, data = "")
    ptr = Leptris::XML::FFI.leptris_pi_node_create(@c_ptr, target.to_s, data.to_s)
    raise Leptris::XML::Error, "leptris_pi_node_create failed" if ptr.null?
    Leptris::XML::Node.wrap(ptr, self)
  end

  def fragment(markup)
    Leptris::XML::DocumentFragment.parse(markup, self)
  end

  def dup
    raw = Leptris::XML::FFI.leptris_document_copy(@c_ptr)
    raise Leptris::XML::Error, "leptris_document_copy failed" if raw.null?
    self.class.wrap(raw)
  end
  alias_method :clone, :dup

  def doctype
    ptr = Leptris::XML::FFI.leptris_document_internal_subset(@c_ptr)
    return nil if ptr.null?
    Leptris::XML::DocType.new(ptr, self)
  end
  alias_method :internal_subset, :doctype

  def to_xml(indent: 0, no_decl: false, encoding: nil)
    raise Leptris::XML::UseAfterFreeError if @freed.state == :freed
    return "" if @c_ptr.nil?
    Leptris::XML::Serialization.to_xml(
      Leptris::XML::FFI.method(:leptris_document_serialize_into), @c_ptr,
      indent: indent, no_decl: no_decl, encoding: encoding)
  end
  alias_method :to_s, :to_xml
  alias_method :serialize, :to_xml

  def save(path, **opts)
    opts_struct, _encoding_anchor = Leptris::XML::Serialization.build_options(
      indent: opts.fetch(:indent, 0),
      no_decl: opts.fetch(:no_decl, false),
      encoding: opts[:encoding])
    status = Leptris::XML::FFI.leptris_document_save_file(
      @c_ptr, path, opts_struct.pointer)
    Leptris::XML::FFI.check_status(status)
    self
  end

  def canonicalize(version = Leptris::XML::FFI::C14N_1_0,
                   inclusive_namespaces = nil,
                   with_comments: false,
                   exclusive: false,
                   mode: nil)
    raise Leptris::XML::UseAfterFreeError if @freed.state == :freed
    return "" if @c_ptr.nil?
    resolved_mode = mode || (exclusive ? Leptris::XML::FFI::C14N_MODE_EXCLUSIVE
                                       : Leptris::XML::FFI::C14N_MODE_CANONICAL)
    Leptris::XML::Serialization.canonicalize(
      Leptris::XML::FFI.method(:leptris_c14n_canonicalize_ex), @c_ptr,
      version: version, mode: resolved_mode,
      inclusive_namespaces: inclusive_namespaces,
      with_comments: with_comments)
  end
  alias_method :c14n, :canonicalize

  def free
    return if @freed.state == :freed
    @freed.state = :freed
    Leptris::XML::FFI.leptris_document_free(@c_ptr) unless @c_ptr.nil?
    @c_ptr = nil
    @wrapper_cache.clear
  end

  # Enable the first-party EXSLT-style extension pack on this
  # document: str:/set:/math: prefixed functions (replace, tokenize,
  # split, concat, padding; distinct, intersection, difference,
  # leading, trailing; max, min, abs, sqrt, power) as native C
  # handlers. Returns self for chaining.
  def exslt
    Leptris::XML::FFI.check_status(
      Leptris::XML::FFI.leptris_exslt_enable(@c_ptr))
    self
  end

  # Document-level processing instructions (not tree nodes):
  # an array of [target, data] pairs in document order.
  def processing_instructions
    if readonly? && instance_variable_defined?(:@processing_instructions)
      return @processing_instructions
    end
    count = Leptris::XML::FFI.leptris_document_pi_count(@c_ptr)
    result = count.times.map do |i|
      [Leptris::XML::FFI.leptris_document_pi_target(@c_ptr, i),
       Leptris::XML::FFI.leptris_document_pi_data(@c_ptr, i)]
    end
    @processing_instructions = result if readonly?
    result
  end

  # Append a document-level processing instruction. Returns self.
  def add_pi(target, data = "")
    witness = Leptris::XML::FFI.leptris_document_add_pi(
      @c_ptr, target.to_s, data.to_s)
    raise Leptris::XML::Error, "leptris_document_add_pi failed" if witness.null?
    self
  end

  # Marks the document read-only: tree mutations raise
  # Leptris::XML::ReadOnlyError, and read paths memoize aggressively
  # (names, content, children, attributes) since they can never go
  # stale. The C document is also frozen (advisory upstream). One-way.
  def readonly!
    Leptris::XML::FFI.leptris_document_freeze(@c_ptr)
    @readonly = true
    self
  end

  def readonly?
    @readonly == true
  end

  # The most recent error recorded against this document, or nil.
  def last_error
    msg = Leptris::XML::FFI.leptris_document_last_error(@c_ptr)
    msg.nil? || msg.empty? ? nil : msg
  end

  def name; "document"; end
  def document; self; end
  def encoding
    return nil if @c_ptr.nil?
    Leptris::XML::FFI.leptris_document_encoding(@c_ptr)
  end

  include Leptris::XML::Searchable
end
