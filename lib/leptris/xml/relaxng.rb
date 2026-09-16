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
    # libleptris 1.9.179 (#878): errors accumulate — every failure
    # from the validate call is returned, not just the first.
    def validate(document)
      ok = Leptris::XML::FFI.leptris_rng_validate(@handle,
                                                  document.c_ptr)
      return [] if ok != 0
      count = Leptris::XML::FFI.leptris_rng_error_count(@handle)
      return [Leptris::XML::FFI.leptris_rng_error(@handle)].compact if count.zero?
      # Jing's rendering for every accumulated error, matching the
      # single-error accessor's format ("line:col: error: msg").
      Array.new(count) do |i|
        msg = Leptris::XML::FFI.leptris_rng_error_message(@handle, i)
        next nil if msg.nil?
        line = Leptris::XML::FFI.leptris_rng_error_line(@handle, i)
        col = Leptris::XML::FFI.leptris_rng_error_column(@handle, i)
        line > 0 ? "#{line}:#{col}: error: #{msg}" : msg
      end.compact
    end

    def valid?(document)
      Leptris::XML::FFI.leptris_rng_validate(@handle,
                                             document.c_ptr) != 0
    end

    # Structured errors: [{ line:, column:, message: }] — the fields
    # callers need for log formatting, instead of re-parsing the
    # Jing-form strings from #validate. Empty when valid. Message,
    # line, and column carry Jing's exact attribution (libleptris
    # >= 1.9.180).
    def validate_errors(document)
      ok = Leptris::XML::FFI.leptris_rng_validate(@handle,
                                                  document.c_ptr)
      return [] if ok != 0
      count = Leptris::XML::FFI.leptris_rng_error_count(@handle)
      return [] if count.zero?
      Array.new(count) do |i|
        msg = Leptris::XML::FFI.leptris_rng_error_message(@handle, i)
        next nil if msg.nil?
        {
          line: Leptris::XML::FFI.leptris_rng_error_line(@handle, i),
          column: Leptris::XML::FFI.leptris_rng_error_column(@handle, i),
          message: msg,
        }
      end.compact
    end
  end
end
