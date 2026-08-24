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

  # +ffi_function+ is a bound FFI function taking (c_ptr, opts_ptr):
  # leptris_document_serialize or leptris_element_serialize.
  def self.to_xml(ffi_function, c_ptr, indent: 0, no_decl: false, encoding: nil)
    opts =
      if indent.to_i.zero? && !no_decl && encoding.nil?
        DEFAULT_OPTIONS
      else
        opts, _encoding_anchor = build_options(
          indent: indent, no_decl: no_decl, encoding: encoding)
        opts
      end
    str_ptr = ffi_function.call(c_ptr, opts.pointer)
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
