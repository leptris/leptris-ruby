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
