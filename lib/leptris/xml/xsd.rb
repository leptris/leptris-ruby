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
      tri_state(
        Leptris::XML::FFI.leptris_xsd_simple_valid(
          @handle, type_name.to_s, lexical.to_s),
        "#{type_name.inspect} is not a simpleType in this schema")
    end

    # Slices 3-4 (libleptris 1.9.321, #1075): whole-instance
    # validation — element declarations, attribute rows (required
    # + typed + lenient qualified spellings), text lexical checks,
    # and child content models through the Thompson NFA. Returns
    # true/false.
    def valid?(document)
      tri_state(
        Leptris::XML::FFI.leptris_xsd_validate(
          @handle, document.c_ptr), "invalid document handle")
    end

    # The enumerated failure list of the last #validate run
    # (empty when valid; the NEXT validate replaces the list).
    def validate_errors(document)
      valid?(document)
      Leptris::XML::FFI.leptris_xsd_error_count(@handle).times.map do |i|
        Leptris::XML::FFI.leptris_xsd_error_at(@handle, i)
      end
    end

    # Slice 3 direct face: a child SEQUENCE against a top-level
    # element declaration's compiled content model (occurrence
    # bounds, xs:any wildcards). +children+ are child Nodes (name
    # + effective namespace extracted per child). Unknown element
    # declarations raise (the -1 contract).
    def content_valid?(element_name, children)
      kids = children.to_a
      nb, na = Leptris::XML::CStringArray.to_c(
        kids.map { |c| c.name.to_s })
      ub, ua = Leptris::XML::CStringArray.to_c(
        kids.map { |c| child_ns_uri(c) })
      tri_state(
        Leptris::XML::FFI.leptris_xsd_content_valid(
          @handle, element_name.to_s, nb, ub, kids.size),
        "#{element_name.inspect} is not a top-level element declaration")
    end

    private

    # A child's effective namespace URI (nil = none) — read
    # through its own c_ptr, so docless wrappers work.
    def child_ns_uri(node)
      uri = Leptris::XML::FFI.leptris_element_namespace(node.c_ptr)
      uri.nil? || uri.empty? ? "" : uri
    end

    # The C faces' 1/0/-1 contract: true/false, with -1 raising —
    # a silent false would mean "no such declaration/type", which
    # callers must never confuse with "invalid input".
    def tri_state(code, unknown_message)
      case code
      when 1 then true
      when 0 then false
      else raise ArgumentError, unknown_message
      end
    end
  end
end
