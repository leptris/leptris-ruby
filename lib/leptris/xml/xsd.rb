# frozen_string_literal: true

require "ffi"

module Leptris::XML::XSD
  module_function

  def compile(schema_xml)
    Schema.compile(schema_xml)
  end

  # Compile from a file path (libleptris >= 1.9.326): unreadable
  # files raise; malformed schemas compile to an error-carrying
  # handle, exactly like .compile.
  def compile_file(path)
    Schema.compile_file(path)
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

    # Deterministic drop (#362.3 / moxml): frees the compiled
    # schema NOW instead of waiting for GC — long-lived validation
    # services holding dozens of schemas stop parking engine-side
    # trees for the process lifetime. The AutoPointer's GC
    # finalizer is disarmed first (autorelease=false), so the free
    # happens exactly once. Faces on a released schema raise.
    #
    #   schema = Leptris::XML::XSD.compile_file(path)
    #   schema.release  # => true
    #   schema.released? # => true
    def release
      return true if released?
      @handle.autorelease = false
      Leptris::XML::FFI.leptris_xsd_free(@handle)
      @released = true
      true
    end

    def released?
      instance_variable_defined?(:@released) ? @released : false
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

    # Compile from a file path: the engine reads it directly.
    def self.compile_file(path)
      status = ::FFI::MemoryPointer.new(:int)
      raw = Leptris::XML::FFI.leptris_xsd_compile_file(path.to_s, status)
      if raw.null?
        raise Leptris::XML::Error,
          "schema file unreadable (status #{status.read_int}): #{path}"
      end
      new(Handle.new(raw))
    end

    # Number of top-level schema declarations the compiler
    # recognized (elements, types, groups, ...).
    def declaration_count
      check_released!
      Leptris::XML::FFI.leptris_xsd_declaration_count(@handle)
    end

    # The schema's effective version (libleptris 1.9.382, moxml#460
    # item 2): "1.1" when the root carries @version="1.1" — the
    # engine then applies 1.1 semantics (xs:alternative CTA,
    # xs:assert) — else "1.0". Consumers scope 1.0-only checks
    # against it.
    def version
      check_released!
      unless Leptris::XML::FFI.respond_to?(:leptris_xsd_version)
        raise Leptris::XML::Error,
              'Schema#version requires libleptris 1.9.382+ '               '(the leptris_xsd_version face)'
      end
      Leptris::XML::FFI.leptris_xsd_version(@handle) || '1.0'
    end

    # The engine's schema-level error message, or nil when the
    # schema compiled cleanly.
    def error
      check_released!
      msg = Leptris::XML::FFI.leptris_xsd_error(@handle)
      msg.nil? || msg.empty? ? nil : msg
    end

    # Slice 2 (libleptris 1.9.319, #1075): lexical validation of
    # +lexical+ against the user simpleType +type_name+ (local
    # name) — restriction chains validate every hop's facets,
    # cycle-guarded. Unknown type names raise (the -1 contract).
    def simple_valid?(type_name, lexical)
      check_released!
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
      check_released!
      tri_state(
        Leptris::XML::FFI.leptris_xsd_validate(
          @handle, document.c_ptr), "invalid document handle")
    end

    # The enumerated failure list of the last #validate run
    # (empty when valid; the NEXT validate replaces the list).
    def validate_errors(document)
      check_released!
      valid?(document)
      Leptris::XML::FFI.leptris_xsd_error_count(@handle).times.map do |i|
        Leptris::XML::FFI.leptris_xsd_error_at(@handle, i)
      end
    end

    # The structured report (libleptris 1.9.382, moxml#460/#1841):
    # one hash per finding — kind (element-decl / attribute-use /
    # content-model / simpleType-facet / type-resolution /
    # assertion / identity-constraint), component (declaring
    # schema component), line, column, message (the same text
    # validate_errors carries). Requires the 1.9.382 engine.
    StructuredError = Struct.new(:kind, :component, :line, :column,
                                 :message)

    def structured_errors(document)
      check_released!
      valid?(document)
      unless Leptris::XML::FFI.respond_to?(:leptris_xsd_error_report)
        raise Leptris::XML::Error,
              'structured_errors requires libleptris 1.9.382+ ' \
              '(the leptris_xsd_error_report face)'
      end
      out = ::FFI::MemoryPointer.new(:pointer)
      n = Leptris::XML::FFI.leptris_xsd_error_report(@handle, out)
      rows = out.get_pointer(0)
      return [] if n.zero? || rows.null?

      # C layout: kind* / component* / uint line / uint column /
      # message* — 32 bytes per record with tail padding.
      (0...n).map do |i|
        ptr = rows + (i * 32)
        kind = ptr.get_pointer(0)
        component = ptr.get_pointer(8)
        line = ptr.get_uint32(16)
        column = ptr.get_uint32(20)
        message = ptr.get_pointer(24)
        StructuredError.new(
          kind.nil? ? nil : kind.read_string,
          component.nil? ? nil : component.read_string,
          line, column,
          message.nil? ? nil : message.read_string
        )
      end
    end

    # Slice 3 direct face: a child SEQUENCE against a top-level
    # element declaration's compiled content model (occurrence
    # bounds, xs:any wildcards). +children+ are child Nodes (name
    # + effective namespace extracted per child). Unknown element
    # declarations raise (the -1 contract).
    def content_valid?(element_name, children)
      check_released!
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

    def check_released!
      raise Leptris::XML::UseAfterFreeError,
            "schema released (moxml #362.3)" if released?
    end

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
