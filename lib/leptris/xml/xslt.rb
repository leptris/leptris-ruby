# frozen_string_literal: true

require "ffi"

module Leptris::XML::XSLT
  module_function

  def parse(stylesheet_xml)
    Stylesheet.parse(stylesheet_xml)
  end

  def parse_file(path)
    Stylesheet.parse_file(path)
  end

  # A compiled XSLT 1.0 stylesheet (libleptris 1.9.1): the stylesheet
  # parses ONCE into an immutable instruction forest — patterns to
  # XPath ASTs, selects through the compiled-XPath path — then applies
  # to any number of documents with no re-parsing.
  #
  #     style = Leptris::XML::XSLT.parse(<<~XSL)
  #       <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
  #         <xsl:template match="/"><out><xsl:value-of select="count(//item)"/></out></xsl:template>
  #       </xsl:stylesheet>
  #     XSL
  #     style.apply_to(doc)      # => result Document (queryable tree)
  #     style.serialize(doc)     # => String (fragments and top-level
  #                              #    text nodes preserved)
  #
  class Stylesheet
    FFI_PTR_SIZE = ::FFI.type_size(:pointer)
    private_constant :FFI_PTR_SIZE

    # GC-managed compiled handle.
    class Handle < ::FFI::AutoPointer
      def self.release(ptr)
        Leptris::XML::FFI.leptris_xslt_free(ptr)
      end
    end

    # Compile a stylesheet. Raises XPathError on a stylesheet syntax
    # error (detail on the thread-global last error).
    def self.parse(stylesheet_xml)
      raw = Leptris::XML::FFI.leptris_xslt_parse(
        stylesheet_xml.to_s, stylesheet_xml.to_s.bytesize)
      if raw.null?
        raise Leptris::XML::XPathError,
          "stylesheet parse failed: #{Leptris::XML::FFI.leptris_last_error}"
      end
      new(Handle.new(raw))
    end

    # Compile from a file. Resolves §2.7 embedded stylesheets
    # (xml-stylesheet PI with an href="#id" fragment) when the file's
    # root is not itself a stylesheet.
    def self.parse_file(path)
      raw = Leptris::XML::FFI.leptris_xslt_parse_file(path.to_s)
      if raw.null?
        raise Leptris::XML::XPathError,
          "stylesheet parse failed: #{Leptris::XML::FFI.leptris_last_error}"
      end
      new(Handle.new(raw))
    end

    def initialize(handle)
      @handle = handle
    end

    # Apply to +document+ (not modified) and return the result tree
    # as an owning Document — query it with xpath/css like any other.
    #
    # params (#360, engine 1.9.288 semantics): top-level xsl:param
    # overrides as a Hash of name => value. Values evaluate as
    # XPath EXPRESSIONS — the libxslt `params` convention callers
    # know from nokogiri (whose quote_params exists to add the
    # quotes): "7 * 6" binds 42, "'7'" binds the string "7",
    # "string(/r/@v)" reads the source. A malformed expression
    # fails the transform. Absent names keep select/@default.
    def apply_to(document, params: nil)
      raw, buffer, = with_param_pairs(params) do |pairs, count|
        if pairs
          Leptris::XML::FFI.leptris_xslt_apply_params(
            @handle, document.c_ptr, pairs, count)
        else
          Leptris::XML::FFI.leptris_xslt_apply(@handle, document.c_ptr)
        end
      end
      buffer&.free
      if raw.null?
        raise Leptris::XML::XPathError,
          "transform failed: #{document.last_error || Leptris::XML::FFI.leptris_last_error}"
      end
      Leptris::XML::Document.wrap(raw)
    end

    # Apply and serialize in one call — keeps top-level text nodes and
    # result fragments that the tree API would flatten. params: as
    # #apply_to.
    def serialize(document, params: nil)
      str_ptr, buffer, = with_param_pairs(params) do |pairs, count|
        if pairs
          Leptris::XML::FFI.leptris_xslt_apply_string_params(
            @handle, document.c_ptr, pairs, count)
        else
          Leptris::XML::FFI.leptris_xslt_apply_string(
            @handle, document.c_ptr)
        end
      end
      buffer&.free
      Leptris::XML::FFI.read_owned_string(str_ptr)
    end

    # Flattens a params Hash into the engine's flat char** pairs
    # array (borrowed for the C call's lifetime — allocated here,
    # freed by the caller; the per-string MemoryPointers stay
    # anchored until the call returns).
    def with_param_pairs(params)
      return yield(nil, 0) if params.nil? || params.empty?
      unless params.is_a?(Hash)
        raise ArgumentError, "params must be a Hash of name => value"
      end

      entries = params.keys.map(&:to_s)
                      .zip(params.values.map { |v| v.nil? ? "" : v.to_s })
      strings = entries.flatten.map { |s| ::FFI::MemoryPointer.from_string(s) }
      buffer = ::FFI::MemoryPointer.new(:pointer, strings.size)
      strings.each_with_index do |ptr, i|
        buffer.put_pointer(i * FFI_PTR_SIZE, ptr)
      end
      [yield(buffer, entries.size), buffer, strings]
    end
  end
end
