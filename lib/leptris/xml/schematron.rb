# frozen_string_literal: true

require "ffi"

module Leptris::XML::Schematron
  module_function

  def parse(schema_xml, phase: nil)
    Schema.parse(schema_xml, phase: phase)
  end

  def parse_file(path, phase: nil)
    Schema.parse_file(path, phase: phase)
  end

  # A compiled Schematron schema (libleptris >= 1.9.126): parse
  # once — optionally selecting a PHASE, which activates only its
  # patterns — then validate any number of documents. #validate
  # returns the SVRL report as a queryable Document; #valid?
  # answers the boolean.
  #
  #     sch = Leptris::XML::Schematron.parse(schema_xml)
  #     sch.valid?(doc)      # => true/false
  #     svrl = sch.validate(doc)   # => Document (svrl:schema root)
  #     sch = Leptris::XML::Schematron.parse(schema_xml, phase: "Basic")
  #
  class Schema
    class Handle < ::FFI::AutoPointer
      def self.release(ptr)
        Leptris::XML::FFI.leptris_schematron_free(ptr)
      end
    end

    def self.parse(schema_xml, phase: nil)
      xml = schema_xml.to_s
      raw =
        if phase
          Leptris::XML::FFI.leptris_schematron_parse_phase(
            xml, xml.bytesize, phase.to_s, nil)
        else
          Leptris::XML::FFI.leptris_schematron_parse(xml, xml.bytesize, nil)
        end
      if raw.null?
        raise Leptris::XML::Error,
          "schema parse failed: #{Leptris::XML::FFI.leptris_last_error}"
      end
      new(Handle.new(raw))
    end

    def self.parse_file(path, phase: nil)
      raw =
        if phase
          xml = File.read(path)
          Leptris::XML::FFI.leptris_schematron_parse_phase(
            xml, xml.bytesize, phase.to_s, nil)
        else
          Leptris::XML::FFI.leptris_schematron_parse_file(path.to_s, nil)
        end
      if raw.null?
        raise Leptris::XML::Error,
          "schema parse failed: #{Leptris::XML::FFI.leptris_last_error}"
      end
      new(Handle.new(raw))
    end

    def initialize(handle)
      @handle = handle
    end

    # The SVRL report as a Document (svrl:schema root — query
    # failed-assert / successful-report elements like any other
    # tree), or the schema-level error text.
    def validate(document)
      report = Leptris::XML::FFI.leptris_schematron_validate(
        @handle, document.c_ptr)
      if report.null?
        Leptris::XML::FFI.leptris_schematron_error(@handle)
      else
        Leptris::XML::Document.wrap(report)
      end
    end

    def valid?(document)
      Leptris::XML::FFI.leptris_schematron_valid(
        @handle, document.c_ptr) != 0
    end
  end
end
