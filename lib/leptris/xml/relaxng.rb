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
  #     rng.validate_errors(doc) # => [] or [{line:, column:, message:}]
  #     rng.validate_report(doc) # => [] or [{kind:, message:, offender:, ...}]
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
      structured = validate_errors(document)
      unless structured.empty?
        return structured.map do |e|
          e[:line] > 0 ? "#{e[:line]}:#{e[:column]}: error: #{e[:message]}"
                        : e[:message]
        end
      end
      # Invalid verdict with nothing accumulated: the back-compat
      # single-error accessor is the last resort (nil-safe).
      return [] if valid?(document)
      [Leptris::XML::FFI.leptris_rng_error(@handle)].compact
    end

    def valid?(document)
      Leptris::XML::FFI.leptris_rng_validate(@handle,
                                             document.c_ptr) != 0
    end

    # Structured errors: [{ line:, column:, message: }] — the fields
    # callers need for log formatting, instead of re-parsing the
    # Jing-form strings from #validate. Empty when valid. Message,
    # line, and column carry Jing's exact attribution (libleptris
    # >= 1.9.179, upstream #878). Rendered from #validate_report —
    # the single enumeration of the error surface.
    def validate_errors(document)
      validate_report(document).map do |r|
        { line: r[:line], column: r[:column], message: r[:message] }
      end
    end

    # The whole validation report, one C call (libleptris >= 1.9.190):
    # [{ kind:, message:, offender:, line:, column: }] — empty when
    # valid. `kind` is the #1126 failure-class taxonomy
    # ("missing-required-attr", "attr-not-allowed", ...), `offender`
    # the attributed element/attribute name (nil when unknown).
    # Strings are read into Ruby copies before returning.
    def validate_report(document)
      ok = Leptris::XML::FFI.leptris_rng_validate(@handle,
                                                  document.c_ptr)
      return [] if ok != 0
      out = ::FFI::MemoryPointer.new(:pointer)
      count = Leptris::XML::FFI.leptris_rng_error_report(@handle, out)
      return [] if count.zero?
      base = out.read_pointer
      return [] if base.null?
      record = Leptris::XML::FFI::RngErrorRecord
      Array.new(count) do |i|
        r = record.new(base + i * record.size)
        {
          kind: r[:kind],
          message: r[:message],
          offender: r[:offender],
          line: r[:line],
          column: r[:column],
        }
      end
    end
  end
end
