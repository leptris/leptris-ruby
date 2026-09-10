# frozen_string_literal: true

require "ffi"

module Leptris::XML::Schematron
  module_function

  def parse(schema_xml, phase: nil)
    Schema.parse(schema_xml, phase: phase)
  end

  def parse_file(path)
    Schema.parse_file(path)
  end

  # A compiled ISO Schematron schema (libleptris >= 1.9.126):
  # the conformance corpus gate is 50/50 against
  # schematron/schematron-conformance. Parse once, validate any
  # number of documents. Validity = zero failed asserts; the SVRL
  # report carries locations, tests and messages.
  #
  #     sch = Leptris::XML::Schematron.parse(schema_xml)
  #     sch.valid?(doc)     # => true/false
  #     svrl = sch.validate(doc)   # => Leptris::XML::Document (SVRL)
  #
  class Schema
    # GC-managed compiled handle.
    class Handle < ::FFI::AutoPointer
      def self.release(ptr)
        Leptris::XML::FFI.leptris_schematron_free(ptr)
      end
    end

    # Compile a schema from XML text. Raises Error on a schema
    # error (multiply-defined variables, undefined variable
    # references, unknown queryBinding...). An optional phase id
    # activates only the patterns that phase selects.
    def self.parse(schema_xml, phase: nil)
      xml = schema_xml.to_s
      raw =
        if phase.nil? || phase.empty?
          Leptris::XML::FFI.leptris_schematron_parse(
            xml, xml.bytesize, nil)
        else
          Leptris::XML::FFI.leptris_schematron_parse_phase(
            xml, xml.bytesize, phase.to_s, nil)
        end
      if raw.null?
        raise Leptris::XML::Error,
          "schema parse failed: #{Leptris::XML::FFI.leptris_last_error}"
      end
      new(Handle.new(raw))
    end

    def self.parse_file(path)
      raw = Leptris::XML::FFI.leptris_schematron_parse_file(
        path.to_s, nil)
      if raw.null?
        raise Leptris::XML::Error,
          "schema parse failed: #{Leptris::XML::FFI.leptris_last_error}"
      end
      new(Handle.new(raw))
    end

    def initialize(handle)
      @handle = handle
    end

    # Validity = zero failed asserts (successful reports do not
    # invalidate — the ISO semantics of the public API).
    def valid?(document)
      Leptris::XML::FFI.leptris_schematron_valid(
        @handle, document.c_ptr) != 0
    end

    # The full SVRL report as a Leptris document:
    # svrl:schematron-output with failed-assert /
    # successful-report entries carrying @test, @location and
    # svrl:text.
    def validate(document)
      raw = Leptris::XML::FFI.leptris_schematron_validate(
        @handle, document.c_ptr)
      return nil if raw.null?
      svrl = Leptris::XML::FFI.read_owned_string(
        Leptris::XML::FFI.leptris_document_serialize(raw, nil))
      Leptris::XML::FFI.leptris_document_free(raw)
      return nil if svrl.empty?
      Leptris::XML::Document.parse(svrl)
    end
  end
end
