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
    # Per-document weak-ref cache for Node wrappers, keyed on c_ptr
    # address. Eliminates re-allocation when the same node is accessed
    # repeatedly (e.g. via children, siblings, multiple xpath calls).
    # Dies with the Document — no stale entries pointing at freed memory.
    @wrapper_cache = ObjectSpace::WeakMap.new
  end

  def self.parse(xml_or_io)
    xml = xml_or_io.respond_to?(:read) ? xml_or_io.read : xml_or_io.to_s
    if xml.empty?
      raise Leptris::XML::ParseError, "empty input"
    end
    status_ptr = ::FFI::MemoryPointer.new(:int)
    raw = Leptris::XML::FFI.leptris_parse_string(xml, xml.bytesize, status_ptr)
    if raw.null?
      status = status_ptr.read_int
      raise Leptris::XML::ParseError,
        "leptris_parse_string failed (status=#{status})"
    end
    wrap(raw)
  end

  def self.parse_file(path)
    status_ptr = ::FFI::MemoryPointer.new(:int)
    raw = Leptris::XML::FFI.leptris_parse_file(path, status_ptr)
    if raw.null?
      status = status_ptr.read_int
      raise Leptris::XML::ParseError,
        "leptris_parse_file failed (status=#{status})"
    end
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
    Leptris::XML::Element.new(ptr, self)
  end

  def create_element(name)
    ptr = Leptris::XML::FFI.leptris_element_create(@c_ptr, name)
    raise Leptris::XML::Error, "leptris_element_create failed" if ptr.null?
    Leptris::XML::Element.new(ptr, self)
  end

  def create_text_node(content)
    ptr = Leptris::XML::FFI.leptris_text_node_create(@c_ptr, content.to_s)
    raise Leptris::XML::Error, "leptris_text_node_create failed" if ptr.null?
    Leptris::XML::Text.new(ptr, self)
  end

  def create_comment(content)
    ptr = Leptris::XML::FFI.leptris_comment_node_create(@c_ptr, content.to_s)
    raise Leptris::XML::Error, "leptris_comment_node_create failed" if ptr.null?
    Leptris::XML::Comment.new(ptr, self)
  end

  def create_cdata(content)
    ptr = Leptris::XML::FFI.leptris_cdata_node_create(@c_ptr, content.to_s)
    raise Leptris::XML::Error, "leptris_cdata_node_create failed" if ptr.null?
    Leptris::XML::CDATA.new(ptr, self)
  end

  def create_processing_instruction(target, data = "")
    ptr = Leptris::XML::FFI.leptris_pi_node_create(@c_ptr, target.to_s, data.to_s)
    raise Leptris::XML::Error, "leptris_pi_node_create failed" if ptr.null?
    Leptris::XML::ProcessingInstruction.new(ptr, self)
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
    opts, enc_ptr = build_serialize_options(indent: indent, no_decl: no_decl, encoding: encoding)
    str_ptr = Leptris::XML::FFI.leptris_document_serialize(@c_ptr, opts.pointer)
    return "" if str_ptr.null?
    str_ptr.read_string.tap { |s| Leptris::XML::FFI.leptris_free_string(str_ptr) }
  end
  alias_method :to_s, :to_xml
  alias_method :serialize, :to_xml

  def save(path, **opts)
    opts_struct, enc_ptr = build_serialize_options(
      indent: opts.fetch(:indent, 0),
      no_decl: opts.fetch(:no_decl, false),
      encoding: opts[:encoding])
    status = Leptris::XML::FFI.leptris_document_save_file(@c_ptr, path, opts_struct.pointer)
    raise Leptris::XML::Error,
      Leptris::XML::FFI.leptris_status_string(status) unless status == Leptris::XML::FFI::LEPTRIS_OK
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
    ns_ptr, _anchor = Leptris::XML.c14n_build_ns_pointer(inclusive_namespaces)
    flags = with_comments ? 1 : 0
    str_ptr = Leptris::XML::FFI.leptris_c14n_canonicalize_ex(
      @c_ptr, version, resolved_mode, ns_ptr, flags)
    return "" if str_ptr.null?
    str_ptr.read_string.tap { Leptris::XML::FFI.leptris_free_string(str_ptr) }
  end
  alias_method :c14n, :canonicalize

  def free
    return if @freed.state == :freed
    @freed.state = :freed
    Leptris::XML::FFI.leptris_document_free(@c_ptr) unless @c_ptr.nil?
    @c_ptr = nil
  end

  def name; "document"; end
  def document; self; end
  def encoding
    return nil if @c_ptr.nil?
    Leptris::XML::FFI.leptris_document_encoding(@c_ptr)
  end

  private

  def build_serialize_options(indent:, no_decl:, encoding:)
    opts = Leptris::XML::FFI::SerializeOptions.new
    opts[:indent] = indent.to_i
    opts[:xml_declaration] = no_decl ? 0 : 1
    enc_ptr = nil
    if encoding
      enc_ptr = ::FFI::MemoryPointer.from_string(encoding.to_s)
      opts[:encoding] = enc_ptr
    end
    [opts, enc_ptr]
  end

  include Leptris::XML::Searchable
end
