# frozen_string_literal: true

# Owns the SerializeOptions lifecycle and the owned-string read for
# document and subtree serialization/canonicalization. Document and
# Element expose one-line methods over this module — the options
# struct, the encoding anchor, the C call, and the read-and-free all
# live here.
module Leptris::XML::Serialization
  # The default options struct (indent 0, declaration on, no encoding
  # override) is constant: build it once and reuse its pointer on the
  # fast path instead of allocating a fresh struct per call.
  DEFAULT_OPTIONS, _default_anchor = begin
    opts = Leptris::XML::FFI::SerializeOptions.new
    opts[:indent] = 0
    opts[:xml_declaration] = 1
    opts[:encoding] = nil
    [opts, nil]
  end
  private_constant :DEFAULT_OPTIONS

  # +ffi_function+ is a bound _serialize_into function. The buffer
  # cycle lives at the FFI seam (FFI.serialize_into_string); this
  # module owns only options selection and construction.
  def self.to_xml(ffi_function, c_ptr, indent: 0, no_decl: false, encoding: nil)
    opts =
      if indent.to_i.zero? && !no_decl && encoding.nil?
        DEFAULT_OPTIONS
      else
        opts, _encoding_anchor = build_options(
          indent: indent, no_decl: no_decl, encoding: encoding)
        opts
      end
    Leptris::XML::FFI.serialize_into_string(ffi_function, c_ptr, opts.pointer)
  end

  # Display-form document serialization (libleptris 1.9.9, #129):
  # the ext struct's indent_text hands ALL whitespace to the
  # formatter — text and mixed content indent too. Display-oriented:
  # the output is NOT guaranteed to round-trip byte-exactly.
  INDENT_TEXT_EXT = begin
    ext = Leptris::XML::FFI::SerializeExtStruct.new
    ext[:indent_text] = 1
    ext
  end
  private_constant :INDENT_TEXT_EXT

  def self.to_xml_display(c_ptr, indent: 0, no_decl: false, encoding: nil)
    opts, encoding_anchor = build_options(
      indent: indent, no_decl: no_decl, encoding: encoding)
    str_ptr = Leptris::XML::FFI.leptris_document_serialize_ext_sized(
      c_ptr, opts.pointer, INDENT_TEXT_EXT.pointer, INDENT_TEXT_EXT.size)
    Leptris::XML::FFI.read_owned_string(str_ptr)
  end

  # Indent-unit serialization (libleptris 1.9.22, #633 —
  # leptris-ruby#109): Nokogiri's indent_text semantics — the unit
  # string replaces the default spaces, repeated `indent` times per
  # depth level, standard layout otherwise. The engine emits ONE
  # copy of the unit string per level (options->indent is ignored
  # when a unit is set), so the binding multiplies unit x indent to
  # reach Nokogiri's repeat count.
  def self.to_xml_indent_unit(c_ptr, unit, indent: 0, no_decl: false,
                              encoding: nil)
    opts, encoding_anchor = build_options(
      indent: indent, no_decl: no_decl, encoding: encoding)
    ext = Leptris::XML::FFI::SerializeExtStruct.new
    unit_anchor = ::FFI::MemoryPointer.from_string(
      indent.positive? ? unit.to_s * indent : unit.to_s)
    ext[:indent_unit] = unit_anchor
    str_ptr = Leptris::XML::FFI.leptris_document_serialize_ext_sized(
      c_ptr, opts.pointer, ext.pointer, ext.size)
    Leptris::XML::FFI.read_owned_string(str_ptr)
  end

  # +ffi_function+ is a bound FFI function taking
  # (c_ptr, version, mode, ns_ptr, flags): leptris_c14n_canonicalize_ex
  # or leptris_c14n_canonicalize_subtree_ex.
  def self.canonicalize(ffi_function, c_ptr, version:, mode:,
                        inclusive_namespaces: nil, with_comments: false)
    ns_ptr, _ns_anchor = Leptris::XML::CStringArray.to_c(inclusive_namespaces)
    str_ptr = ffi_function.call(c_ptr, version, mode, ns_ptr, with_comments ? 1 : 0)
    Leptris::XML::FFI.read_owned_string(str_ptr)
  end

  # XML-escapes text content for inner_html: & first, then < >
  # and CR (libxml2 emits &#xD; for a bare carriage return).
  ESCAPE_TEXT = {
    "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\r" => "&#xD;",
  }.freeze
  private_constant :ESCAPE_TEXT
  ESCAPE_TEXT_RE = /[&<>\r]/.freeze
  private_constant :ESCAPE_TEXT_RE

  def self.escape_text(string)
    string.gsub(ESCAPE_TEXT_RE, ESCAPE_TEXT)
  end

  # Element-face indent unit (leptris-ruby#109 residual 2): no
  # element-level ext-serialize entry exists yet, so the unit path
  # rounds the subtree through serialization into a fresh document
  # (leptris_element_copy drops COMMENT/PI children —
  # leptris/leptris#696, leptris-ruby#115) and serializes that
  # document without a declaration — identical output to the
  # element serializer for the standard layout, with the unit and
  # every child kind intact.
  def self.to_xml_element_unit(element, unit, indent: 0)
    document = Leptris::XML::Document.parse(element.to_xml)
    begin
      to_xml_indent_unit(document.c_ptr, unit,
                         indent: indent, no_decl: true)
    ensure
      document.free
    end
  end

  # Builds a SerializeOptions struct. Returns [opts, encoding_anchor];
  # the anchor must stay referenced while opts is in an FFI call.
  def self.build_options(indent: 0, no_decl: false, encoding: nil)
    opts = Leptris::XML::FFI::SerializeOptions.new
    opts[:indent] = indent.to_i
    opts[:xml_declaration] = no_decl ? 0 : 1
    encoding_anchor = nil
    if encoding
      encoding_anchor = ::FFI::MemoryPointer.from_string(encoding.to_s)
      opts[:encoding] = encoding_anchor
    end
    [opts, encoding_anchor]
  end
end
