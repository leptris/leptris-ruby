# frozen_string_literal: true

require "ffi"

module Leptris::XML::RelaxNG
  module_function

  def parse(schema_xml)
    Schema.parse(schema_xml)
  end

  def parse_file(path)
    Schema.parse_file(path)
  end

  # A compiled RELAX NG schema (libleptris >= 1.9.115): Jing-parity
  # validation against the standard DOM — parse once, validate any
  # number of documents. Schema errors publish to the thread-global
  # error channel, so failures raise with the engine's detail
  # ("unknown pattern element: ...", "cannot open schema file ...").
  #
  #     rng = Leptris::XML::RelaxNG.parse(schema_xml)
  #     rng.valid?(doc)      # => true/false
  #     rng.validate(doc)    # => [] or ["1:0: error: element ..."]
  #
  class Schema
    # GC-managed compiled handle.
    class Handle < ::FFI::AutoPointer
      def self.release(ptr)
        Leptris::XML::FFI.leptris_rng_free(ptr)
      end
    end

    # Compile a schema from XML text. Raises Error on a schema
    # error (detail via leptris_last_error).
    def self.parse(schema_xml)
      xml = schema_xml.to_s
      raw = Leptris::XML::FFI.leptris_rng_parse(xml, xml.bytesize, nil)
      if raw.null?
        raise Leptris::XML::Error,
          "schema parse failed: #{Leptris::XML::FFI.leptris_last_error}"
      end
      new(Handle.new(raw))
    end

    # Compile from a file; <include href="..."> resolves relative to
    # the file's directory (Jing's override rules apply).
    def self.parse_file(path)
      raw = Leptris::XML::FFI.leptris_rng_parse_file(path.to_s, nil)
      if raw.null?
        raise Leptris::XML::Error,
          "schema parse failed: #{Leptris::XML::FFI.leptris_last_error}"
      end
      new(Handle.new(raw))
    end

    def initialize(handle)
      @handle = handle
    end

    # Nokogiri shape: an array of error strings (the engine emits
    # Jing's "line:col: error: message" form), empty when valid.
    def validate(document)
      ok = Leptris::XML::FFI.leptris_rng_validate(@handle,
                                                  document.c_ptr)
      return [] if ok != 0
      [Leptris::XML::FFI.leptris_rng_error(@handle)].compact
    end

    def valid?(document)
      Leptris::XML::FFI.leptris_rng_validate(@handle,
                                             document.c_ptr) != 0
    end
  end
end
