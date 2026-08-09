# frozen_string_literal: true

require "ffi"

class Taurus::XML::Document
  attr_reader :c_ptr

  def initialize(c_ptr = nil)
    @c_ptr = c_ptr
    @freed = false
  end

  def self.parse(xml_or_io)
    xml = xml_or_io.respond_to?(:read) ? xml_or_io.read : xml_or_io.to_s
    if xml.empty?
      raise Taurus::XML::ParseError, "empty input"
    end
    status_ptr = ::FFI::MemoryPointer.new(:int)
    raw = Taurus::XML::FFI.taurus_parse_string(xml, xml.bytesize, status_ptr)
    if raw.null?
      status = status_ptr.read_int
      raise Taurus::XML::ParseError,
        "taurus_parse_string failed (status=#{status})"
    end
    new(::FFI::AutoPointer.new(raw, Taurus::XML::FFI.method(:taurus_document_free)))
  end

  def self.parse_file(path)
    status_ptr = ::FFI::MemoryPointer.new(:int)
    raw = Taurus::XML::FFI.taurus_parse_file(path, status_ptr)
    if raw.null?
      status = status_ptr.read_int
      raise Taurus::XML::ParseError,
        "taurus_parse_file failed (status=#{status})"
    end
    new(::FFI::AutoPointer.new(raw, Taurus::XML::FFI.method(:taurus_document_free)))
  end

  def root
    raise Taurus::XML::UseAfterFreeError if @freed
    return nil if @c_ptr.nil?
    ptr = Taurus::XML::FFI.taurus_document_root(@c_ptr)
    return nil if ptr.null?
    Taurus::XML::Element.new(ptr, self)
  end

  def create_element(name)
    ptr = Taurus::XML::FFI.taurus_element_create(@c_ptr, name)
    raise Taurus::XML::Error, "taurus_element_create failed" if ptr.null?
    Taurus::XML::Element.new(ptr, self)
  end

  def create_text_node(content)
    ptr = Taurus::XML::FFI.taurus_text_node_create(@c_ptr, content.to_s)
    raise Taurus::XML::Error, "taurus_text_node_create failed" if ptr.null?
    Taurus::XML::Text.new(ptr, self)
  end

  def create_comment(content)
    ptr = Taurus::XML::FFI.taurus_comment_node_create(@c_ptr, content.to_s)
    raise Taurus::XML::Error, "taurus_comment_node_create failed" if ptr.null?
    Taurus::XML::Comment.new(ptr, self)
  end

  def create_cdata(content)
    ptr = Taurus::XML::FFI.taurus_cdata_node_create(@c_ptr, content.to_s)
    raise Taurus::XML::Error, "taurus_cdata_node_create failed" if ptr.null?
    Taurus::XML::CDATA.new(ptr, self)
  end

  def create_processing_instruction(target, data = "")
    ptr = Taurus::XML::FFI.taurus_pi_node_create(@c_ptr, target.to_s, data.to_s)
    raise Taurus::XML::Error, "taurus_pi_node_create failed" if ptr.null?
    Taurus::XML::ProcessingInstruction.new(ptr, self)
  end

  def fragment(markup)
    Taurus::XML::DocumentFragment.parse(markup, self)
  end

  def dup
    raw = Taurus::XML::FFI.taurus_document_copy(@c_ptr)
    raise Taurus::XML::Error, "taurus_document_copy failed" if raw.null?
    self.class.new(::FFI::AutoPointer.new(raw, Taurus::XML::FFI.method(:taurus_document_free)))
  end
  alias_method :clone, :dup

  def doctype
    ptr = Taurus::XML::FFI.taurus_document_internal_subset(@c_ptr)
    return nil if ptr.null?
    Taurus::XML::DocType.new(ptr, self)
  end
  alias_method :internal_subset, :doctype

  def to_xml(indent: 0, no_decl: false, encoding: nil)
    raise Taurus::XML::UseAfterFreeError if @freed
    return "" if @c_ptr.nil?
    opts, enc_ptr = build_serialize_options(indent: indent, no_decl: no_decl, encoding: encoding)
    str_ptr = Taurus::XML::FFI.taurus_document_serialize(@c_ptr, opts.pointer)
    return "" if str_ptr.null?
    str_ptr.read_string.tap { |s| Taurus::XML::FFI.taurus_free_string(str_ptr) }
  end
  alias_method :to_s, :to_xml
  alias_method :serialize, :to_xml

  def save(path, **opts)
    opts_struct, enc_ptr = build_serialize_options(
      indent: opts.fetch(:indent, 0),
      no_decl: opts.fetch(:no_decl, false),
      encoding: opts[:encoding])
    status = Taurus::XML::FFI.taurus_document_save_file(@c_ptr, path, opts_struct.pointer)
    raise Taurus::XML::Error,
      Taurus::XML::FFI.taurus_status_string(status) unless status == Taurus::XML::FFI::TAURUS_OK
    self
  end

  def canonicalize(version = Taurus::XML::FFI::C14N_1_0,
                   inclusive_namespaces = nil,
                   with_comments: false,
                   exclusive: false,
                   mode: nil)
    raise Taurus::XML::UseAfterFreeError if @freed
    return "" if @c_ptr.nil?
    resolved_mode = mode || (exclusive ? Taurus::XML::FFI::C14N_MODE_EXCLUSIVE
                                       : Taurus::XML::FFI::C14N_MODE_CANONICAL)
    ns_ptr, _anchor = Taurus::XML.c14n_build_ns_pointer(inclusive_namespaces)
    flags = with_comments ? 1 : 0
    str_ptr = Taurus::XML::FFI.taurus_c14n_canonicalize_ex(
      @c_ptr, version, resolved_mode, ns_ptr, flags)
    return "" if str_ptr.null?
    str_ptr.read_string.tap { Taurus::XML::FFI.taurus_free_string(str_ptr) }
  end
  alias_method :c14n, :canonicalize

  def free
    return if @freed || @c_ptr.nil?
    @c_ptr.free
    @freed = true
    @c_ptr = nil
  end

  def name; "document"; end
  def document; self; end
  def encoding
    return nil if @c_ptr.nil?
    Taurus::XML::FFI.taurus_document_encoding(@c_ptr)
  end

  private

  def build_serialize_options(indent:, no_decl:, encoding:)
    opts = Taurus::XML::FFI::SerializeOptions.new
    opts[:indent] = indent.to_i
    opts[:xml_declaration] = no_decl ? 0 : 1
    enc_ptr = nil
    if encoding
      enc_ptr = ::FFI::MemoryPointer.from_string(encoding.to_s)
      opts[:encoding] = enc_ptr
    end
    [opts, enc_ptr]
  end

  include Taurus::XML::Searchable
end
