# frozen_string_literal: true

require "ffi"

module Leptris::XML
  # DTD validation (the libleptris 1.9.202-exported surface, the
  # leptris validate --dtd CLI's library face): parse an internal
  # subset, optionally merge an external subset (the application
  # owns I/O — read the resource named by the DOCTYPE system id
  # and hand the bytes over), then validate any number of documents.
  # The RelaxNG shape: parse once, validate many; errors carry
  # message/element/line/column.
  #
  #     dtd = Leptris::XML::DTD.parse(<<~DTD)
  #       <!ELEMENT book (title, author+)>
  #       <!ATTLIST book id ID #REQUIRED>
  #     DTD
  #     dtd.valid?(doc)
  #     dtd.validate(doc)  # => [{message:, element:, line:, column:}]
  #
  module DTD
    module_function

    def parse(dtd_content)
      DTDHandle.parse(dtd_content)
    end

    # The document's own internal subset (from its DOCTYPE), as a
    # validatable handle: document-owned, never freed by the caller.
    # Extend it with an external subset via #merge_external_subset.
    def from_document(document)
      DTDHandle.wrap_owned(
        Leptris::XML::FFI.leptris_document_get_dtd(document.c_ptr))
    end

    # One struct-free convenience: validate +first_error. Returns
    # nil when valid.
    def first_error(document, dtd_content)
      DTDHandle.parse(dtd_content).first_error(document)
    end

    class DTDHandle
      def self.parse(dtd_content)
        content = dtd_content.to_s
        raw = Leptris::XML::FFI.leptris_dtd_parse(
          content, content.bytesize)
        if raw.null?
          raise Leptris::XML::Error,
            "DTD parse failed: #{Leptris::XML::FFI.leptris_last_error}"
        end
        new(OwnedHandle.new(raw))
      end

      def self.wrap_owned(ptr)
        new(nil, ptr)
      end

      class OwnedHandle < ::FFI::AutoPointer
        def self.release(ptr)
          Leptris::XML::FFI.leptris_dtd_free(ptr)
        end
      end

      def initialize(owned, doc_owned_ptr = nil)
        @owned = owned
        @ptr = doc_owned_ptr || owned
      end

      def c_ptr
        @ptr
      end

      # Merge an external subset (the application reads the resource;
      # the library never does I/O). First declaration of a name wins,
      # so the internal subset is never overridden.
      def merge_external_subset(content)
        c = content.to_s
        rc = Leptris::XML::FFI.leptris_dtd_parse_external_subset(
          c_ptr, c, c.bytesize)
        raise Leptris::XML::Error, "external subset merge failed" if rc.negative?
        self
      end

      def valid?(document)
        validate(document).empty?
      end

      # [{ message:, element:, line:, column: }] — empty when valid.
      def validate(document)
        err = Leptris::XML::FFI::DTDErrorStruct.new
        rc = Leptris::XML::FFI.leptris_dtd_validate(
          document.c_ptr, c_ptr, err)
        return [] if rc == 1
        return [{ message: "internal validation error" }] if rc.negative?
        message = err[:message]
        return [{ message: "validation failed" }] if message.nil?
        [{
          message: message,
          element: err[:element_name],
          line: err[:line],
          column: err[:column],
        }]
      ensure
        Leptris::XML::FFI.leptris_dtd_error_free(err) unless rc == 1
      end

      # nil when valid — the single-error convenience.
      def first_error(document)
        validate(document).first
      end
    end
  end
end
