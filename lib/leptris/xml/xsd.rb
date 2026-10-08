# frozen_string_literal: true

require "ffi"

module Leptris::XML::XSD
  module_function

  def compile(schema_xml)
    Schema.compile(schema_xml)
  end

  # Slice 2 (libleptris 1.9.319, #1075): built-in lexical table.
  # +builtin+ takes the "xs:NAME" reference spelling. Returns
  # true/false; an unknown table name raises — a silent false
  # would let misspelled types validate nothing forever.
  def builtin_valid?(builtin, lexical)
    r = Leptris::XML::FFI.leptris_xsd_builtin_valid(
      builtin.to_s, lexical.to_s)
    case r
    when 1 then true
    when 0 then false
    else
      raise ArgumentError,
        "#{builtin.inspect} is not in the tier-1 built-in table"
    end
  end

  # A compiled XSD schema (libleptris >= 1.9.318, #1075 tier-1):
  # the compilation surface — a declaration census and schema-level
  # error reporting. Validation is a later tier and not exposed yet.
  #
  #     schema = Leptris::XML::XSD.compile(xsd_text)
  #     schema.declaration_count  # => top-level schema declarations
  #     schema.error              # => nil, or the engine's message
  #
  class Schema
    # GC-managed compiled handle.
    class Handle < ::FFI::AutoPointer
      def self.release(ptr)
        Leptris::XML::FFI.leptris_xsd_free(ptr)
      end
    end

    # Compile a schema from XML text. Raises Error when the text is
    # not usable at all (not well-formed, no root); schema-level
    # problems compile to a handle whose #error carries the detail
    # — the tier-1 contract.
    def self.compile(schema_xml)
      xml = schema_xml.to_s
      status = ::FFI::MemoryPointer.new(:int)
      raw = Leptris::XML::FFI.leptris_xsd_compile(xml, xml.bytesize, status)
      if raw.null?
        raise Leptris::XML::Error,
          "schema compile failed (status #{status.read_int}): " \
          "#{Leptris::XML::FFI.leptris_last_error}"
      end
      new(Handle.new(raw))
    end

    def initialize(handle)
      @handle = handle
    end

    # Number of top-level schema declarations the compiler
    # recognized (elements, types, groups, ...).
    def declaration_count
      Leptris::XML::FFI.leptris_xsd_declaration_count(@handle)
    end

    # The engine's schema-level error message, or nil when the
    # schema compiled cleanly.
    def error
      msg = Leptris::XML::FFI.leptris_xsd_error(@handle)
      msg.nil? || msg.empty? ? nil : msg
    end

    # Slices 3-4 (libleptris 1.9.321, #1075): instance validation.
    # +document+ is a Leptris::XML::Document. Returns the engine's
    # accumulated error messages ([] = valid); -1 (validator could
    # not run) raises — a silent [] would read as "valid".
    def validate(document)
      r = Leptris::XML::FFI.leptris_xsd_validate(@handle, document.c_ptr)
      case r
      when 1 then []
      when 0
        Leptris::XML::FFI.leptris_xsd_error_count(@handle).times.map do |i|
          msg = Leptris::XML::FFI.leptris_xsd_error_at(@handle, i)
          msg.nil? || msg.empty? ? "validation failed" : msg
        end
      else
        raise Leptris::XML::Error,
          "validator could not run on this document"
      end
    end

    def valid?(document)
      validate(document).empty?
    end

    # Slice 3: content-model check for one element's children —
    # +children+ is the child element local-name list, +child_ns+
    # their (possibly nil) namespace URI list. Unknown element
    # names raise (the -1 contract).
    def content_valid?(element_name, children, child_ns: nil)
      names = children.map(&:to_s)
      ns = child_ns || Array.new(names.size)
      names_ptr = ::FFI::MemoryPointer.new(:pointer, names.size + 1)
      ns_ptr = ::FFI::MemoryPointer.new(:pointer, names.size + 1)
      name_ptrs = names.map { |n| ::FFI::MemoryPointer.from_string(n) }
      ns_ptrs = ns.each_with_index.map do |u, idx|
        u && !u.to_s.empty? ? ::FFI::MemoryPointer.from_string(u.to_s) : nil
      end
      name_ptrs.each_with_index { |p, idx| names_ptr.put_pointer(idx * 8, p) }
      names_ptr.put_pointer(names.size * 8, nil)
      ns_ptrs.each_with_index { |p, idx| ns_ptr.put_pointer(idx * 8, p) }
      ns_ptr.put_pointer(names.size * 8, nil)
      r = Leptris::XML::FFI.leptris_xsd_content_valid(
        @handle, element_name.to_s, names_ptr, ns_ptr, names.size)
      case r
      when 1 then true
      when 0 then false
      else
        raise ArgumentError,
          "#{element_name.inspect} is not a global element in this schema"
      end
    end

    # Slice 2 (libleptris 1.9.319, #1075): lexical validation of
    # +lexical+ against the user simpleType +type_name+ (local
    # name) — restriction chains validate every hop's facets,
    # cycle-guarded. Unknown type names raise (the -1 contract).
    def simple_valid?(type_name, lexical)
      r = Leptris::XML::FFI.leptris_xsd_simple_valid(
        @handle, type_name.to_s, lexical.to_s)
      case r
      when 1 then true
      when 0 then false
      else
        raise ArgumentError,
          "#{type_name.inspect} is not a simpleType in this schema"
      end
    end
  end
end
